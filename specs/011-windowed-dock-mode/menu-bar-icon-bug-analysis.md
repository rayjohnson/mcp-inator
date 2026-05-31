# Menu Bar Icon Bug — Analysis & Fix

## The Bug

When the user switches from menu bar mode to dock mode via Preferences, the menu bar icon
remained visible. Clicking it did nothing (the popover is empty in dock mode by design), but
the icon should not appear at all.

---

## Root Cause

SwiftUI owns the `NSStatusItem` that backs `MenuBarExtra`. On every state change it re-evaluates
`body` and reconciles the scene graph. Any direct manipulation of `NSStatusItem.isVisible`
(e.g., via the KVC `value(forKey: "statusItems")` approach that was tried first) gets overridden
on SwiftUI's next update cycle because the scene still says "this MenuBarExtra is present."

The fix must go through SwiftUI itself, not around it.

---

## What Was Tried and Why It Failed

### Attempt 1 — KVC `setStatusItemsVisible(false)`

```swift
let items = (value(forKey: "statusItems") as? [NSStatusItem]) ?? []
items.forEach { $0.isVisible = false }
```

**Result**: Icon stayed visible. SwiftUI re-asserted `isVisible = true` on its next update pass.

### Attempt 2 — Conditional scene `if !showInDock { MenuBarExtra { } }`

**Result**: Compiler crash ("failed to produce diagnostic for expression"). `@SceneBuilder`
cannot infer a concrete `some Scene` type when there is no `else` branch.

### Attempt 3 — `if/else` with two `MenuBarExtra` branches

**Result**: Explicit compiler error: *"closure containing control flow statement cannot be used
with result builder 'SceneBuilder'"*. This Xcode version's `@SceneBuilder` does not support
`if`/`else` at all in `var body: some Scene`.

### Rejected Approach — `init()` wiring via `launchAction`

An approach was considered where `appDelegate.launchAction` was set in `mcp_inatorApp.init()`
to defer `wireWindowController()` until `applicationDidFinishLaunching`. This was rejected
because accessing `@StateObject` wrapped values inside `init()` bypasses SwiftUI's ownership
of those objects and is an unsupported pattern that can cause undefined behavior.

---

## Implemented Fix

### Part 1 — `MenuBarExtra(isInserted:content:label:)`

SwiftUI provides a documented `MenuBarExtra` initializer (macOS 13.0+) that accepts an
`isInserted: Binding<Bool>` alongside a custom `label:` closure:

```swift
init(
    isInserted: Binding<Bool>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
)
```

Source: https://developer.apple.com/documentation/swiftui/menubarextra/init(isinserted:content:label:)

A single, always-present `MenuBarExtra` scene satisfies `@SceneBuilder` while the binding
controls whether the `NSStatusItem` exists:

```swift
MenuBarExtra(isInserted: Binding(get: { !showInDock }, set: { _ in })) {
    // … popover content …
} label: {
    Image("Inator")
        .onAppear { wireWindowController() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didFinishLaunchingNotification
        )) { _ in
            wireWindowController()
        }
        .onChange(of: showInDock) { newValue in
            if newValue { appDelegate.insertDockModeMenuItems() }
        }
}
.menuBarExtraStyle(.window)
.commands { … }
```

When `showInDock` becomes `true`, `isInserted` becomes `false` → SwiftUI removes the
`NSStatusItem`. When `showInDock` becomes `false`, `isInserted` becomes `true` → SwiftUI
restores it. No KVC, no conditional scene building.

### Part 2 — Dock-Mode Cold Launch

When `isInserted = false` at launch, the status item is not in the menu bar, but SwiftUI
keeps the scene's view graph alive. This means `onReceive(didFinishLaunchingNotification)`
on the label view fires at launch even in dock mode, triggering `wireWindowController()`
which opens the main window.

`AppDelegate.applicationDidFinishLaunching` handles activation policy and Application menu
items independently by reading `UserDefaults` directly (no `@StateObject` dependency):

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    launchAction?()
    launchAction = nil
    if UserDefaults.standard.bool(forKey: "showInDock") {
        NSApp.setActivationPolicy(.regular)
        insertDockModeMenuItems()
    }
}
```

### Part 3 — Mid-Session Dock-Mode Switch

`.onChange(of: showInDock)` on the label view calls `appDelegate.insertDockModeMenuItems()`
when the user switches to dock mode mid-session. The `isInserted` binding handles status item
removal reactively without any explicit closure in `AppModeManager`.

### Part 4 — `@MainActor` on `AppDelegate`

`AppDelegate` was annotated `@MainActor` to fix Swift 6 concurrency errors (accessing
`NSApp.mainMenu`, calling `checkForUpdates()`, etc. from a non-isolated context) that were
surfaced when the file was recompiled.

---

## Files Changed

| File | Change |
|------|--------|
| `mcp_inatorApp.swift` | Single `MenuBarExtra(isInserted:)` replacing conditional scene; `wireWindowController()` sets AppDelegate refs; `onReceive`/`onChange` on label |
| `AppDelegate.swift` | `@MainActor`; `applicationDidFinishLaunching` reads UserDefaults directly for dock-mode setup |
| `AppModeManager.swift` | `setMenuBarVisible` closure added (earlier); no longer set by `wireWindowController()` — replaced by `onChange` |
