# Window Switcher on Current Screen

List and focus the windows on the screen **under your mouse cursor** — the screen
filter that the built-in "Switch Windows" command lacks — plus quick commands to
warp the cursor between screens.

## Commands

| Command | Mode | What it does |
| --- | --- | --- |
| **Switch Windows on Current Screen** | view | Lists application windows on the screen under the cursor (toggle to **All screens** from the search-bar dropdown), searchable by app name and window title. Select one to raise and focus it. |
| **Focus Next Screen** | no-view | Moves the mouse cursor to the center of the next screen (cyclic). |
| **Focus Previous Screen** | no-view | Moves the mouse cursor to the center of the previous screen (cyclic). |

The default scope of the switcher ("Current screen" / "All screens") is configurable
in the command preferences.

## How it works

Raycast's public `WindowManagement` API can only enumerate the *active desktop* and
cannot focus an arbitrary window, so this extension bundles a tiny native helper
(`assets/cursor-screen`, built from `swift/cursor-screen.swift`) that:

- reports the screen under the cursor (`NSEvent.mouseLocation` + `NSScreen`),
- warps the cursor between screens (`CGWarpMouseCursorPosition`),
- lists on-screen windows (`CGWindowListCopyWindowInfo`), and
- raises/focuses a chosen window (Accessibility `AXRaise` + app activation).

The TypeScript commands invoke it via `child_process.execFile`.

## Permissions

Grant these to **Raycast** in System Settings → Privacy & Security:

- **Accessibility** — required to focus/raise windows.
- **Screen Recording** — optional; only needed to read window **titles**. Without
  it, windows are still listed and searchable by application name.

Cursor warping (Focus Next/Previous Screen) needs no special permission.

## Development

```bash
npm install
npm run build:swift   # recompile the native helper into assets/cursor-screen
npm run dev           # run the extension in Raycast
```

The compiled `assets/cursor-screen` binary is committed so the extension works
without a Swift toolchain; rebuild it with `npm run build:swift` after editing
`swift/cursor-screen.swift`.
