// cursor-screen — tiny AppKit/Accessibility helper for the
// "Window Switcher on Current Screen" Raycast extension.
//
// Subcommands (selected via argv):
//   cursor-screen current        → prints the NSScreenNumber of the screen under the cursor
//   cursor-screen next           → warps the cursor to the center of the next screen (cyclic)
//   cursor-screen previous       → warps the cursor to the center of the previous screen (cyclic)
//   cursor-screen list           → prints a JSON array of on-screen windows
//                                  [{ id, pid, app, title, screen, x, y, width, height }]
//   cursor-screen focus <id>     → raises the window with CGWindowID <id> and activates its app
//
// Permissions:
//   - Cursor warp (next/previous): no special permission.
//   - Window titles in `list`:     require Screen Recording permission (app name always available).
//   - `focus`:                     requires Accessibility permission.

import AppKit
import ApplicationServices

// MARK: - Screen helpers

func screenNumber(_ screen: NSScreen) -> Int {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
}

/// (index, screen) of the NSScreen currently under the mouse cursor.
func screenUnderCursor() -> (index: Int, screen: NSScreen)? {
    let mouse = NSEvent.mouseLocation // bottom-left origin, primary screen at (0,0)
    let screens = NSScreen.screens
    if let idx = screens.firstIndex(where: { NSMouseInRect(mouse, $0.frame, false) }) {
        return (idx, screens[idx])
    }
    return nil
}

/// CoreGraphics global rect (top-left origin) for an NSScreen (bottom-left origin).
func cgRect(for screen: NSScreen) -> CGRect {
    let primaryHeight = NSScreen.screens[0].frame.height
    let f = screen.frame
    return CGRect(x: f.origin.x, y: primaryHeight - f.maxY, width: f.width, height: f.height)
}

/// NSScreenNumber of the screen whose CG rect contains `point` (top-left origin).
func screenNumberContaining(point: CGPoint) -> Int {
    for screen in NSScreen.screens where cgRect(for: screen).contains(point) {
        return screenNumber(screen)
    }
    return NSScreen.screens.first.map(screenNumber) ?? 0
}

// MARK: - list

func listWindows() {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        print("[]")
        return
    }

    var items: [[String: Any]] = []
    for info in infoList {
        // layer 0 == normal application windows (skip menubar, dock, shadows, …)
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if layer != 0 { continue }

        guard let windowID = info[kCGWindowNumber as String] as? Int else { continue }
        let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
        let app = info[kCGWindowOwnerName as String] as? String ?? ""
        let title = info[kCGWindowName as String] as? String ?? ""

        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { continue }

        // skip tiny helper/HUD windows
        if bounds.width < 50 || bounds.height < 50 { continue }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        items.append([
            "id": windowID,
            "pid": pid,
            "app": app,
            "title": title,
            "screen": screenNumberContaining(point: center),
            "x": Int(bounds.origin.x),
            "y": Int(bounds.origin.y),
            "width": Int(bounds.width),
            "height": Int(bounds.height),
        ])
    }

    if let data = try? JSONSerialization.data(withJSONObject: items),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    } else {
        print("[]")
    }
}

// MARK: - focus

func windowInfo(for windowID: CGWindowID) -> [String: Any]? {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    return list.first { ($0[kCGWindowNumber as String] as? Int) == Int(windowID) }
}

func axFrame(_ window: AXUIElement) -> CGRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
    else { return nil }

    var pos = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    return CGRect(origin: pos, size: size)
}

/// AX position/size live in the same top-left global space as CGWindowBounds,
/// so we match the AX window to the CGWindow by bounds (within a small tolerance).
func axWindowMatches(_ window: AXUIElement, target: CGRect) -> Bool {
    guard let f = axFrame(window) else { return false }
    let tol: CGFloat = 6
    return abs(f.origin.x - target.origin.x) < tol &&
        abs(f.origin.y - target.origin.y) < tol &&
        abs(f.width - target.width) < tol &&
        abs(f.height - target.height) < tol
}

func focusWindow(windowID: CGWindowID) -> Bool {
    guard let info = windowInfo(for: windowID),
          let pidInt = info[kCGWindowOwnerPID as String] as? Int,
          let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
          let target = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { return false }

    let pid = pid_t(pidInt)
    let appAX = AXUIElementCreateApplication(pid)

    var windowsRef: CFTypeRef?
    AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsRef)
    let axWindows = (windowsRef as? [AXUIElement]) ?? []
    let matched = axWindows.first { axWindowMatches($0, target: target) }

    // Bring the owning application forward first…
    NSRunningApplication(processIdentifier: pid)?.activate()

    // …then raise/focus the specific window.
    if let win = matched {
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appAX, kAXFocusedWindowAttribute as CFString, win)
        return true
    }
    return matched != nil
}

// MARK: - entry point

let args = CommandLine.arguments
let cmd = args.dropFirst().first ?? "current"
let screens = NSScreen.screens

switch cmd {
case "current":
    if let (_, screen) = screenUnderCursor() {
        print(screenNumber(screen))
    } else if let primary = screens.first {
        print(screenNumber(primary))
    }

case "next", "previous":
    guard !screens.isEmpty else { exit(1) }
    let curIdx = screenUnderCursor()?.index ?? 0
    let offset = cmd == "next" ? 1 : -1
    let target = screens[(curIdx + offset + screens.count) % screens.count]
    let f = target.frame
    let primaryHeight = screens[0].frame.height
    // NSScreen center (bottom-left) → CGWarp expects top-left origin.
    let cgPoint = CGPoint(x: f.midX, y: primaryHeight - f.midY)
    CGWarpMouseCursorPosition(cgPoint)
    CGAssociateMouseAndMouseCursorPosition(1)

case "list":
    listWindows()

case "focus":
    guard let idStr = args.dropFirst(2).first, let id = UInt32(idStr) else {
        FileHandle.standardError.write("usage: cursor-screen focus <windowID>\n".data(using: .utf8)!)
        exit(1)
    }
    exit(focusWindow(windowID: CGWindowID(id)) ? 0 : 1)

default:
    FileHandle.standardError.write("unknown command: \(cmd)\n".data(using: .utf8)!)
    exit(1)
}
