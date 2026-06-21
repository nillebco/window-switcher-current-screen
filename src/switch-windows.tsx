import {
  Action,
  ActionPanel,
  closeMainWindow,
  environment,
  getPreferenceValues,
  Icon,
  List,
  showToast,
  Toast,
} from "@raycast/api";
import { execFile } from "child_process";
import { join } from "path";
import { useEffect, useMemo, useState } from "react";
import { promisify } from "util";

const run = promisify(execFile);
const BIN = join(environment.assetsPath, "cursor-screen");

type Scope = "current" | "everywhere";

type Win = {
  id: number;
  pid: number;
  app: string;
  title: string;
  screen: number;
  x: number;
  y: number;
  width: number;
  height: number;
};

interface Preferences {
  defaultScope: Scope;
}

export default function SwitchWindows() {
  const prefs = getPreferenceValues<Preferences>();
  const [windows, setWindows] = useState<Win[]>([]);
  const [currentScreen, setCurrentScreen] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [scope, setScope] = useState<Scope>(prefs.defaultScope ?? "current");

  useEffect(() => {
    (async () => {
      try {
        const [{ stdout: screenOut }, { stdout: listOut }] = await Promise.all([
          run(BIN, ["current"]),
          run(BIN, ["list"]),
        ]);
        setCurrentScreen(Number.parseInt(screenOut.trim(), 10));
        setWindows(JSON.parse(listOut) as Win[]);
      } catch (error) {
        await showToast({
          style: Toast.Style.Failure,
          title: "Couldn't list windows",
          message: error instanceof Error ? error.message : String(error),
        });
      } finally {
        setIsLoading(false);
      }
    })();
  }, []);

  const shown = useMemo(() => {
    const filtered =
      scope === "current" && currentScreen != null ? windows.filter((w) => w.screen === currentScreen) : windows;
    return [...filtered].sort((a, b) => a.app.localeCompare(b.app) || a.title.localeCompare(b.title));
  }, [windows, scope, currentScreen]);

  async function focus(win: Win) {
    try {
      await closeMainWindow();
      await run(BIN, ["focus", String(win.id)]);
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Couldn't focus window",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return (
    <List
      isLoading={isLoading}
      searchBarPlaceholder="Search windows by app or title…"
      searchBarAccessory={
        <List.Dropdown tooltip="Scope" value={scope} onChange={(value) => setScope(value as Scope)}>
          <List.Dropdown.Item title="Current screen" value="current" />
          <List.Dropdown.Item title="All screens" value="everywhere" />
        </List.Dropdown>
      }
    >
      {shown.map((win) => (
        <List.Item
          key={win.id}
          icon={Icon.AppWindow}
          title={win.app}
          subtitle={win.title}
          keywords={[win.app, win.title]}
          accessories={[{ tag: `Screen ${win.screen}` }]}
          actions={
            <ActionPanel>
              <Action title="Focus Window" icon={Icon.Eye} onAction={() => focus(win)} />
            </ActionPanel>
          }
        />
      ))}
      {!isLoading && shown.length === 0 && (
        <List.EmptyView
          title="No windows found"
          description={
            scope === "current" ? "No windows on the screen under the cursor." : "No application windows detected."
          }
        />
      )}
    </List>
  );
}
