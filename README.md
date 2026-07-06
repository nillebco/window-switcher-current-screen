# Window Switcher on Current Screen

List and focus the windows on the screen **under your mouse cursor** — the screen
filter that the built-in "Switch Windows" command lacks — plus quick commands to
warp the cursor between screens.

## Commands

| Command | Mode | What it does |
| --- | --- | --- |
| **Switch Windows on Current Screen** | view | Lists application windows on the screen under the cursor (toggle to **All screens** from the search-bar dropdown), searchable by app name and window title. Select one to raise and focus it. |
| **Focus Next Screen** | no-view | Moves the mouse cursor to the center of the next screen (cyclic). |
| **List Screens** | view | Lists all displays with their resolution/position, flagging Main, Built-in/External, and Virtual/Physical. |
| **List Spaces** | view | Lists Mission Control Spaces (Desktops) grouped by display, flagging the current Space. Read-only. |
| **Focus Previous Screen** | no-view | Moves the mouse cursor to the center of the previous screen (cyclic). |
| **Click at Cursor** | no-view | Synthesizes a left mouse click at the current cursor position (`CGEvent`). |
| **Arrange Visible Windows** | no-view | Tiles the windows on the current screen into a weighted binary partition, each window sized in proportion to its current area. Gap between tiles is configurable in preferences. |

The default scope of the switcher ("Current screen" / "All screens") is configurable
in the command preferences.

## How it works

Raycast's public `WindowManagement` API can only enumerate the *active desktop* and
cannot focus an arbitrary window, so this extension bundles a tiny native helper
(`assets/cursor-screen`, built from `swift/cursor-screen.swift`) that:

- reports the screen under the cursor (`NSEvent.mouseLocation` + `NSScreen`),
- warps the cursor between screens (`CGWarpMouseCursorPosition`),
- lists on-screen windows (`CGWindowListCopyWindowInfo`),
- lists displays with their attributes (`NSScreen` + `CGDisplay*`),
- lists Mission Control Spaces read-only via the private SkyLight framework
  (`SLSCopyManagedDisplaySpaces` on the app's own connection — no SIP changes, no
  writes),
- raises/focuses a chosen window (Accessibility `AXRaise` + app activation),
- moves/resizes a window on the current Space (Accessibility `AXPosition`/`AXSize`), and
- clicks at the cursor (`CGEvent` mouse down/up).

The TypeScript commands invoke it via `child_process.execFile`. **Arrange Visible
Windows** computes the layout in TypeScript (weighted binary partition over the
screen's visible area) and applies each rect via the helper. Apps that enforce a
minimum window size are honored best-effort — such a window keeps its position but
may not shrink to its full tile.

## Permissions

Grant these to **Raycast** in System Settings → Privacy & Security:

- **Accessibility** — required to focus/raise windows, move/resize them
  (**Arrange Visible Windows**), and post the synthetic click (**Click at Cursor**).
- **Screen Recording** — optional; only needed to read window **titles**. Without
  it, windows are still listed and searchable by application name.

Cursor warping (Focus Next/Previous Screen) and **List Screens** need no special
permission.

## Development

```bash
npm install
npm run build:swift   # recompile the native helper into assets/cursor-screen
npm run dev           # run the extension in Raycast
```

The compiled `assets/cursor-screen` binary is committed so the extension works
without a Swift toolchain; rebuild it with `npm run build:swift` after editing
`swift/cursor-screen.swift`.
