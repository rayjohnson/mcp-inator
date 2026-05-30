# Research: Windowed App Mode with Menu Bar Toggle

## 1. NSApplicationActivationPolicy — Runtime Switching

**Decision**: Call `NSApp.setActivationPolicy(.regular)` to gain dock presence and `NSApp.setActivationPolicy(.accessory)` to remove it.

**Rationale**: These calls work immediately at runtime with no restart. `.regular` adds the dock icon, enables Cmd+Tab, and makes the app activatable. `.accessory` removes all of that. Must be called on the main thread.

**Gotcha**: Switching from `.accessory` → `.regular` does not automatically bring a window to the front. We must explicitly open the main window after the call. Switching back `.regular` → `.accessory` leaves any open windows visible; we close them first.

---

## 2. SwiftUI Scene Composition — Conditional MenuBarExtra vs Window

**Decision**: Use `if/else` in the SwiftUI `App.body` `@SceneBuilder` to toggle between `MenuBarExtra` (menu bar mode) and `Window + Settings` (dock mode). Observable state drives the condition.

**Rationale**: SwiftUI's `@SceneBuilder` supports `if/else` result-builder syntax. When `showInDock` flips, SwiftUI tears down the old scene tree and constructs the new one. Combined with the `NSApp.setActivationPolicy()` call, the transition is seamless.

**Key detail**: Because `App.body` is re-evaluated on state change, an `AppModeManager` `ObservableObject` owned by the app struct as `@StateObject` will trigger the rebuild correctly.

---

## 3. SwiftUI `Settings` Scene (Preferences window, Cmd+,)

**Decision**: Use SwiftUI's built-in `Settings` scene on macOS 13+.

**Rationale**: `Settings` automatically wires up Cmd+, and the "Settings…" application menu item. Deployment target is macOS 13.0, so this is fully available. Simply declare:

```swift
Settings {
    PreferencesView()
}
```

This gives a standard macOS preferences window with no custom window management code.

---

## 4. Launch at Login — SMAppService

**Decision**: Use `SMAppService.mainApp.register()` / `.unregister()` from the `ServiceManagement` framework.

**Rationale**: `SMAppService` (macOS 13+) is the modern replacement for `SMLoginItemSetEnabled`. No helper bundle required — `mainApp` registers the app itself. No additional entitlements needed. Status is readable via `SMAppService.mainApp.status`.

**Usage**:
```swift
import ServiceManagement
try SMAppService.mainApp.register()   // enable
try SMAppService.mainApp.unregister() // disable
let isEnabled = SMAppService.mainApp.status == .enabled
```

---

## 5. Window Frame Persistence

**Decision**: Use SwiftUI `Window` scene with a stable `id`. SwiftUI/AppKit automatically persists the frame via `NSWindow.frameAutosaveName` when a stable scene ID is set.

**Rationale**: No manual `UserDefaults` frame storage needed. Providing `Window("mcp-inator", id: "main")` gives macOS enough information to save and restore size and position across launches. Off-screen recovery is handled by adding `.defaultPosition(.center)` as a fallback.

---

## 6. Close Window → Quit App Behavior

**Decision**: Implement `NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)` returning `true` when in dock mode, `false` otherwise.

**Rationale**: This is the standard AppKit mechanism for "closing the last window quits the app." The SwiftUI `App` struct can adopt `NSApplicationDelegateAdaptor` to wire this in cleanly without abandoning the SwiftUI App lifecycle.

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

---

## 7. Sidebar Content Sharing

**Decision**: Extract `AgentsTabView` from its current `private` scope inside `MenuBarView` to a package-internal struct in a new file. `ConfigLibraryView` and `CatalogView` are already top-level and require no changes.

**Rationale**: These views must render in both the popover tabs and the `NavigationSplitView` detail area. No logic duplication — same views, different container. The only wrapping that changes is `TabView` (popover) vs `NavigationSplitView` (window).

---

## 8. Application Menu in Dock Mode

**Decision**: Standard SwiftUI `CommandGroup` additions for About and the `Settings` scene handles Preferences (Cmd+,) automatically. No custom `CommandMenu` needed for the initial scope.

**Rationale**: The `Settings` scene auto-inserts "Settings…" into the app menu. About is provided via a `CommandGroup(replacing: .appInfo)` that calls the existing `AboutWindowController`. Quit (Cmd+Q) is free from AppKit.
