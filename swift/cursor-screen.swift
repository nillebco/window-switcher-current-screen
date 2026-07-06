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
//   cursor-screen click [button] → synthesizes a mouse click at the current cursor position
//                                  button ∈ { left (default), right, double }
//   cursor-screen screens        → prints a JSON array of displays with raw attributes
//                                  [{ index, id, name, main, builtin, virtual, vendor, model,
//                                     serial, x, y, width, height }]
//   cursor-screen spaces         → prints a JSON array of Mission Control Spaces per display
//                                  [{ display, displayIdentifier, spaces: [{ index, managedSpaceID,
//                                     type, typeLabel, uuid, current }] }]
//
// Permissions:
//   - Cursor warp (next/previous): no special permission.
//   - Window titles in `list`:     require Screen Recording permission (app name always available).
//   - `focus`:                     requires Accessibility permission.
//   - `click`:                     requires Accessibility permission (to post synthetic events).

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

// MARK: - screens

/// Best-guess "is this a virtual/software display?".
/// BetterDisplay (and other) virtual screens are non-builtin and typically report
/// no real EDID vendor/serial. We combine that with a name-based hint. Raw
/// vendor/model/serial are also emitted so the heuristic can be hardened once we
/// observe what a real BetterDisplay virtual screen reports on this machine.
func isLikelyVirtual(displayID: CGDirectDisplayID, name: String) -> Bool {
    if CGDisplayIsBuiltin(displayID) != 0 { return false }
    let lower = name.lowercased()
    if lower.contains("virtual") || lower.contains("dummy") || lower.contains("betterdisplay") {
        return true
    }
    // No vendor and no serial is unusual for real hardware over DP/HDMI.
    return CGDisplayVendorNumber(displayID) == 0 && CGDisplaySerialNumber(displayID) == 0
}

func listScreens() {
    var items: [[String: Any]] = []
    for (idx, screen) in NSScreen.screens.enumerated() {
        let displayID = CGDirectDisplayID(screenNumber(screen))
        let name = screen.localizedName
        let rect = cgRect(for: screen)
        items.append([
            "index": idx,
            "id": Int(displayID),
            "name": name,
            "main": CGDisplayIsMain(displayID) != 0,
            "builtin": CGDisplayIsBuiltin(displayID) != 0,
            "virtual": isLikelyVirtual(displayID: displayID, name: name),
            "vendor": Int(CGDisplayVendorNumber(displayID)),
            "model": Int(CGDisplayModelNumber(displayID)),
            "serial": Int(CGDisplaySerialNumber(displayID)),
            "x": Int(rect.origin.x),
            "y": Int(rect.origin.y),
            "width": Int(rect.width),
            "height": Int(rect.height),
        ])
    }

    if let data = try? JSONSerialization.data(withJSONObject: items),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    } else {
        print("[]")
    }
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

// MARK: - click

enum ClickButton: String {
    case left, right, double

    var cgButton: CGMouseButton { self == .right ? .right : .left }
    var downType: CGEventType { self == .right ? .rightMouseDown : .leftMouseDown }
    var upType: CGEventType { self == .right ? .rightMouseUp : .leftMouseUp }
    var clickCount: Int64 { self == .double ? 2 : 1 }
}

/// Synthesizes a click at the cursor's current position.
/// A double-click is two down/up pairs with clickState 1 then 2.
func clickAtCursor(_ button: ClickButton) -> Bool {
    let src = CGEventSource(stateID: .hidSystemState)
    guard let loc = CGEvent(source: src)?.location else { return false }

    func post(clickState: Int64) -> Bool {
        guard let down = CGEvent(mouseEventSource: src, mouseType: button.downType,
                                 mouseCursorPosition: loc, mouseButton: button.cgButton),
              let up = CGEvent(mouseEventSource: src, mouseType: button.upType,
                               mouseCursorPosition: loc, mouseButton: button.cgButton)
        else { return false }
        down.setIntegerValueField(.mouseEventClickState, value: clickState)
        up.setIntegerValueField(.mouseEventClickState, value: clickState)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    for state in 1...button.clickCount where !post(clickState: state) { return false }
    return true
}

// MARK: - spaces (Mission Control)

/// Maps each display's CoreGraphics UUID string → its localized name, so the
/// SkyLight "Display Identifier" (a UUID, or "Main") can be shown as a real name.
func displayUUIDToName() -> [String: String] {
    var map: [String: String] = [:]
    for screen in NSScreen.screens {
        let displayID = CGDirectDisplayID(screenNumber(screen))
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            let uuid = CFUUIDCreateString(nil, cfUUID) as String
            map[uuid] = screen.localizedName
        }
    }
    return map
}

func spaceTypeLabel(_ type: Int) -> String {
    switch type {
    case 0: return "desktop"
    case 4: return "fullscreen"
    default: return "type\(type)"
    }
}

/// Reads Mission Control Spaces (read-only) via the private SkyLight framework.
/// Uses the app's own connection — no SIP changes, no Dock injection, no writes.
func listSpaces() {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
          let cidSym = dlsym(handle, "SLSMainConnectionID"),
          let copySym = dlsym(handle, "SLSCopyManagedDisplaySpaces")
    else {
        FileHandle.standardError.write("SkyLight unavailable\n".data(using: .utf8)!)
        print("[]")
        return
    }

    typealias MainConnectionIDFn = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    let mainConnectionID = unsafeBitCast(cidSym, to: MainConnectionIDFn.self)
    let copyManagedDisplaySpaces = unsafeBitCast(copySym, to: CopyManagedDisplaySpacesFn.self)

    guard let displays = copyManagedDisplaySpaces(mainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
        print("[]")
        return
    }

    let nameMap = displayUUIDToName()
    var out: [[String: Any]] = []
    for display in displays {
        let identifier = display["Display Identifier"] as? String ?? "?"
        let displayName = identifier == "Main"
            ? (NSScreen.main?.localizedName ?? "Main")
            : (nameMap[identifier] ?? identifier)
        let currentID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int

        var spaces: [[String: Any]] = []
        for (i, sp) in (display["Spaces"] as? [[String: Any]] ?? []).enumerated() {
            let managedSpaceID = sp["ManagedSpaceID"] as? Int ?? sp["id64"] as? Int ?? 0
            let type = sp["type"] as? Int ?? 0
            spaces.append([
                "index": i + 1,
                "managedSpaceID": managedSpaceID,
                "type": type,
                "typeLabel": spaceTypeLabel(type),
                "uuid": sp["uuid"] as? String ?? "",
                "current": managedSpaceID == currentID,
            ])
        }
        out.append([
            "display": displayName,
            "displayIdentifier": identifier,
            "spaces": spaces,
        ])
    }

    if let data = try? JSONSerialization.data(withJSONObject: out),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    } else {
        print("[]")
    }
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

case "screens":
    listScreens()

case "spaces":
    listSpaces()

case "focus":
    guard let idStr = args.dropFirst(2).first, let id = UInt32(idStr) else {
        FileHandle.standardError.write("usage: cursor-screen focus <windowID>\n".data(using: .utf8)!)
        exit(1)
    }
    exit(focusWindow(windowID: CGWindowID(id)) ? 0 : 1)

case "click":
    let button = ClickButton(rawValue: args.dropFirst(2).first ?? "left") ?? .left
    exit(clickAtCursor(button) ? 0 : 1)

default:
    FileHandle.standardError.write("unknown command: \(cmd)\n".data(using: .utf8)!)
    exit(1)
}
