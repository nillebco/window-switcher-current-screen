import { closeMainWindow, environment, getPreferenceValues, showHUD } from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

type Win = { id: number; app: string; title: string; screen: number; width: number; height: number };
type Screen = { id: number; visibleX: number; visibleY: number; visibleWidth: number; visibleHeight: number };
type Rect = { x: number; y: number; w: number; h: number };
type Slot = Rect & { id: number };
type Item = { id: number; weight: number; aspect: number };

interface Preferences {
  gap: string;
}

/** Weight-weighted geometric mean of the group's window aspect ratios (w/h). */
function targetAspect(items: Item[]): number {
  const totalW = items.reduce((s, i) => s + i.weight, 0);
  const ln = items.reduce((s, i) => s + i.weight * Math.log(i.aspect), 0) / totalW;
  return Math.exp(ln);
}

/** How far a rect's aspect ratio is from a target (symmetric in log space). */
function distortion(w: number, h: number, target: number): number {
  return Math.abs(Math.log(w / h / target));
}

/**
 * Aspect-aware binary partition. `items` is sorted by weight descending, so the
 * first candidate split peels off the largest window as a "master". At each level
 * we try every split point AND both orientations (side-by-side vs stacked) and keep
 * the one whose two tiles best match the windows' real aspect ratios. Tile areas
 * stay proportional to window area; the screen is filled with no gaps.
 */
function tile(rect: Rect, items: Item[]): Slot[] {
  if (items.length === 1) return [{ id: items[0].id, ...rect }];
  const total = items.reduce((s, i) => s + i.weight, 0);

  let best: { cost: number; a: Item[]; b: Item[]; ra: Rect; rb: Rect } | null = null;
  let accW = 0;
  for (let k = 1; k < items.length; k++) {
    accW += items[k - 1].weight;
    const a = items.slice(0, k);
    const b = items.slice(k);
    const fracA = accW / total;
    const tA = targetAspect(a);
    const tB = targetAspect(b);

    // side-by-side: left | right
    const hA: Rect = { x: rect.x, y: rect.y, w: rect.w * fracA, h: rect.h };
    const hB: Rect = { x: rect.x + hA.w, y: rect.y, w: rect.w - hA.w, h: rect.h };
    const costH = distortion(hA.w, hA.h, tA) + distortion(hB.w, hB.h, tB);

    // stacked: top / bottom
    const vA: Rect = { x: rect.x, y: rect.y, w: rect.w, h: rect.h * fracA };
    const vB: Rect = { x: rect.x, y: rect.y + vA.h, w: rect.w, h: rect.h - vA.h };
    const costV = distortion(vA.w, vA.h, tA) + distortion(vB.w, vB.h, tB);

    const [cost, ra, rb] = costH <= costV ? [costH, hA, hB] : [costV, vA, vB];
    if (!best || cost < best.cost) best = { cost, a, b, ra, rb };
  }

  return [...tile(best!.ra, best!.a), ...tile(best!.rb, best!.b)];
}

export default async function ArrangeWindows() {
  const gap = Math.max(0, Number.parseInt(getPreferenceValues<Preferences>().gap ?? "8", 10) || 0);
  await closeMainWindow();

  try {
    const [{ stdout: curOut }, { stdout: screensOut }, { stdout: listOut }] = await Promise.all([
      run(BIN, ["current"]),
      run(BIN, ["screens"]),
      run(BIN, ["list"]),
    ]);

    const currentScreen = Number.parseInt(curOut.trim(), 10);
    const screens = JSON.parse(screensOut) as Screen[];
    const screen = screens.find((s) => s.id === currentScreen) ?? screens[0];
    const wins = (JSON.parse(listOut) as Win[]).filter((w) => w.screen === currentScreen);

    if (!screen || wins.length < 2) {
      await showHUD(wins.length < 2 ? "Nothing to arrange (need 2+ windows)" : "No screen found");
      return;
    }

    // Weight by current area and carry each window's aspect ratio so the tiling can
    // keep tiles close to the windows' real shapes. Largest first (master peels off).
    const items: Item[] = wins
      .map((w) => ({ id: w.id, weight: Math.max(1, w.width * w.height), aspect: w.width / Math.max(1, w.height) }))
      .sort((x, y) => y.weight - x.weight);

    const container: Rect = { x: screen.visibleX, y: screen.visibleY, w: screen.visibleWidth, h: screen.visibleHeight };
    const slots = tile(container, items).map((s) => ({
      id: s.id,
      x: Math.round(s.x + gap),
      y: Math.round(s.y + gap),
      w: Math.round(s.w - 2 * gap),
      h: Math.round(s.h - 2 * gap),
    }));

    let ok = 0;
    for (const s of slots) {
      if (s.w < 1 || s.h < 1) continue;
      try {
        await run(BIN, ["set-frame", String(s.id), String(s.x), String(s.y), String(s.w), String(s.h)]);
        ok++;
      } catch {
        // window may be non-resizable or have closed; skip it
      }
    }

    await showHUD(`Arranged ${ok}/${wins.length} window${wins.length === 1 ? "" : "s"}`);
  } catch (error) {
    await showHUD("Couldn't arrange windows");
  }
}
