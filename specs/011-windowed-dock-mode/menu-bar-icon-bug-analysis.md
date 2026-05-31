# Menu Bar Icon Bug — Analysis & Fix Proposal

## The Bug

When the user switches from menu bar mode to dock mode via Preferences, the menu bar icon
remains visible. Clicking it does nothing (the popover is empty in dock mode by design), but
the icon should not be there at all.

---

## Root Cause

SwiftUI owns the `NSStatusItem` that backs `MenuBarExtra`. On every state change it re-evaluates
`body` and reconciles the scene graph. Any direct manipulation of `NSStatusItem.isVisible`
(e.g., via the KVC `value(forKey: "statusItems")` approach we tried) gets overridden on
SwiftUI's next update cycle because the scene still says "this MenuBarExtra is present."

The fix must go through SwiftUI itself, not around it.

---

## What Was Tried and Why It Failed

### Attempt 1 — KVC `setStatusItemsVisible(false)`

```swift
let items = (value(forKey: "statusItems") as? [NSStatusItem]) ?? []
items.forEach { $0.isVisible = false }
```

**Result**: Icon stayed visible after switching. SwiftUI re-asserted `isVisible = true`
on its next update pass because the `MenuBarExtra` scene hadn't changed.

### Attempt 2 — Conditional scene `if !showInDock { MenuBarExtra { } }`

**Result**: Compiler crash ("failed to produce diagnostic for expression") on the
`var body: some Scene` declaration. The Swift result builder for `@SceneBuilder` cannot
infer a concrete `some Scene` type when there is no `else` branch
(the implicit second type is `Never`, which does not conform to `Scene`).

### Attempt 3 — `if/else` with two `MenuBarExtra` branches

```swift
if showInDock {
    MenuBarExtra("", isInserted: .constant(false)) { EmptyView() }
} else {
    MenuBarExtra { … } label: { Image("Inator") }
}
```

**Result**: Explicit compiler error: *"closure containing control flow statement cannot
be used with result builder 'SceneBuilder'"*. This Xcode version's `@SceneBuilder`
does not implement `buildOptional` / `buildEither`, so **no `if`/`else` is allowed in
`var body: some Scene`**.

---

## Proposed Fix

### Part 1 — Use `MenuBarExtra(isInserted:content:label:)`

SwiftUI provides a documented `MenuBarExtra` initializer (macOS 13.0+) that takes an
`isInserted: Binding<Bool>` **alongside** a custom `label:` closure:

```swift
init(
    isInserted: Binding<Bool>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
)
```

Source: https://developer.apple.com/documentation/swiftui/menubarextra/init(isinserted:content:label:)

This keeps a single, always-present `MenuBarExtra` scene in `body` (satisfying
`@SceneBuilder`) while letting SwiftUI itself insert or remove the `NSStatusItem`
based on the binding value.

The binding is computed from `@AppStorage("showInDock")`:

```swift
MenuBarExtra(isInserted: Binding(get: { !showInDock }, set: { _ in })) {
    // … existing popover content …
} label: {
    Image("Inator")   // same custom icon as today
}
.menuBarExtraStyle(.window)
.commands { … }
```

When `showInDock` becomes `true`, `isInserted` becomes `false` → SwiftUI removes the
`NSStatusItem`. When `showInDock` becomes `false`, `isInserted` becomes `true` → SwiftUI
restores it. No KVC, no conditionals.

The `set: { _ in }` ignores the case where the user removes the item via System Settings;
our Preferences toggle is the only intended control.

---

### Part 2 — Dock-Mode Initialization

With `isInserted = false` at launch (dock mode), the status item is never inserted, so
`label.onAppear` never fires, meaning `wireWindowController()` is never called and the
main window never opens.

**Fix**: Wire `appDelegate.launchAction = { wireWindowController() }` in
`mcp_inatorApp.init()`, after `updaterController` is assigned (the point at which all
stored properties are initialized and `self` is legally capturable in an escaping closure).

```swift
init() {
    // … Sentry, Sparkle setup …
    updaterController = SPUStandardUpdaterController(…)

    // All stored properties now initialized.
    appDelegate.appModeManager = appModeManager
    appDelegate.aboutController = aboutController
    appDelegate.preferencesController = preferencesController
    appDelegate.updater = updaterController.updater
    appDelegate.launchAction = { [self] in wireWindowController() }
}
```

`AppDelegate.applicationDidFinishLaunching` (already written) calls `launchAction?()`,
then inserts dock-mode Application menu items if `showInDock == true`.

**Safety of `@StateObject` in `init()`**: Apple's documentation explicitly shows
assigning `_model = StateObject(wrappedValue: …)` inside `View.init()` as a supported
pattern. The backing object is stored in the `StateObject` wrapper itself (not lazily
in SwiftUI's graph), so `appModeManager`, `storeContainer`, etc. accessed in `init()`
return the same instances that `body` will use. For `App` (a singleton), these are
guaranteed to be identical objects throughout the app's lifetime.

**Safety of `appDelegate` in `init()`**: `@NSApplicationDelegateAdaptor` resolves its
`wrappedValue` via `NSApp.delegate`. SwiftUI sets `NSApp.delegate` to the `AppDelegate`
instance before calling `App.init()`, so the delegate is available at that point.

---

### Part 3 — Mid-Session Dock-Mode Switch

When the user toggles dock mode while the app is running, `AppModeManager.setShowInDock`
is called. It calls `setMenuBarVisible?(false)`. We update that closure in
`wireWindowController()` to:

```swift
appModeManager.setMenuBarVisible = { [weak appDelegate] visible in
    if !visible {
        // Switching to dock mode: add Preferences / Check for Updates to the
        // Application menu. Status item removal is handled by isInserted binding.
        appDelegate?.insertDockModeMenuItems()
    }
    // visible == true (switching back): no-op; isInserted binding restores the icon.
}
```

The `NSStatusBar` KVC extension can be deleted.

---

## Complete List of File Changes

| File | Change |
|------|--------|
| `mcp_inatorApp.swift` | `init()`: add AppDelegate wiring + `launchAction` |
| `mcp_inatorApp.swift` | `body`: swap `MenuBarExtra` for `isInserted` variant; remove `appDelegate.appModeManager =` from `onAppear` |
| `mcp_inatorApp.swift` | `wireWindowController()`: update `setMenuBarVisible` closure; remove `NSApp.setActivationPolicy` call (already handled by `AppModeManager`) |
| `mcp_inatorApp.swift` | Remove `ensureSetup()` function and `NSStatusBar` KVC extension |
| `AppDelegate.swift` | No changes needed (already has `launchAction` and `insertDockModeMenuItems()`) |
| `AppModeManager.swift` | No changes needed |

---

## Risk / Open Questions

1. **`@StateObject` in `init()` cross-check**: The documentation pattern involves
   *assigning* `_model = StateObject(…)` in `init()`. Our use case *reads* the already-
   declared `appModeManager` in `init()`. This is a fine distinction — if SwiftUI has
   not yet installed its state graph hooks, reading `wrappedValue` might return the raw
   stored value rather than the graph-managed value. They should be the same object, but
   this is worth a second opinion.

2. **`label.onAppear` timing in menu bar mode**: With `isInserted` controlling insertion,
   `label.onAppear` fires when the status item first appears. In menu bar mode (launched
   fresh or switched back from dock mode), this fires `wireWindowController()`. The guard
   `appModeManager.openMainWindow == nil` prevents double-execution with the `launchAction`
   path. This should be safe but worth reviewing.
