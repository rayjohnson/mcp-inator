# Implementation Plan: Windowed App Mode with Menu Bar Toggle

**Branch**: `011-windowed-dock-mode` | **Date**: 2026-05-30 | **Spec**: [spec.md](spec.md)

## Summary

Add a "Show in Dock" preference that switches mcp-inator between its current menu bar–only popover and a full macOS windowed app with sidebar navigation, dock icon, Cmd+Tab access, and a Preferences window (Cmd+,) containing Show in Dock and Launch at Login toggles. The transition is immediate with no restart. The existing content views (ConfigLibraryView, AgentListView, CatalogView) are reused unchanged.

## Technical Context

**Language/Version**: Swift 6.0 / SwiftUI  
**Primary Dependencies**: AppKit, ServiceManagement (SMAppService), Sparkle (existing), Sentry (existing)  
**Storage**: UserDefaults via `@AppStorage` for mode preference; GRDB (existing) unchanged  
**Testing**: XCTest (existing test suite — 230 tests currently passing)  
**Target Platform**: macOS 13.0+  
**Project Type**: macOS menu bar / desktop app  
**Performance Goals**: Mode switch completes in under 1 second  
**Constraints**: No restart required for mode switch; existing behavior must be fully preserved when showInDock = false  
**Scale/Scope**: Single-user desktop app; ~5 new Swift files, ~1 modified  

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | ✅ PASS | `NavigationSplitView`, `Settings` scene, `SMAppService`, standard AppKit patterns |
| II. Single Source of Truth | ✅ PASS | No config storage changes |
| III. Non-Destructive Configuration | ✅ PASS | No config changes |
| IV. Config Portability | ✅ PASS | No adapter changes |
| V. Simplicity & Discoverability | ✅ PASS | One toggle; default off preserves existing behavior |

No violations. Complexity Tracking table not required.

## Project Structure

### Documentation (this feature)

```text
specs/011-windowed-dock-mode/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── spec.md
├── checklists/
│   └── requirements.md
└── tasks.md             ← Phase 2 output (speckit-tasks)
```

### Source Code Changes

```text
mcp-inator/
├── App/
│   ├── AppDelegate.swift          ← NEW: NSApplicationDelegate (close-window-quits)
│   ├── AppModeManager.swift       ← NEW: showInDock preference + activation policy
│   └── mcp_inatorApp.swift        ← MODIFY: conditional scenes, inject AppModeManager
│
└── UI/
    ├── MainWindowView.swift       ← NEW: NavigationSplitView for dock mode
    ├── PreferencesView.swift      ← NEW: Show in Dock + Launch at Login toggles
    ├── AgentsView.swift           ← NEW: extract AgentsTabView from MenuBarView
    └── MenuBarView.swift          ← MODIFY: remove AgentsTabView (now in AgentsView.swift)

mcp-inatorTests/
└── Unit/
    └── AppModeManagerTests.swift  ← NEW: preference persistence, mode logic
```

## Architecture

### AppModeManager

Central observable that owns the mode preference and orchestrates the transition:

```swift
@MainActor
final class AppModeManager: ObservableObject {
    @AppStorage("showInDock") private(set) var showInDock: Bool = false

    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
        if enabled {
            openMainWindow()
        }
        // Window close is handled by NSApplicationDelegate
    }
}
```

### Scene Composition (mcp_inatorApp)

```swift
var body: some Scene {
    if appModeManager.showInDock {
        Window("mcp-inator", id: "main") {
            MainWindowView()
                .environmentObject(store)
                ...
        }
        .defaultSize(width: 960, height: 620)
        .commands { appCommands }

        Settings {
            PreferencesView()
                .environmentObject(appModeManager)
        }
    } else {
        MenuBarExtra { ... } label: { ... }
    }
}
```

### MainWindowView

```text
NavigationSplitView
  sidebar:
    List with Label rows: Servers · Agents · Catalog
  detail:
    switch selectedSection:
      .servers  → NavigationStack { ConfigLibraryView() }
      .agents   → NavigationStack { AgentsView() }
      .catalog  → NavigationStack { CatalogView() }
```

### PreferencesView

```text
Form
  Section("General")
    Toggle "Show in Dock"      → AppModeManager.setShowInDock(_:)
    Toggle "Launch at Login"   → SMAppService.mainApp.register/unregister
```

### AppDelegate

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        UserDefaults.standard.bool(forKey: "showInDock")
    }
}
```

### About Menu (dock mode)

The existing `AboutWindowController` is reused. A `CommandGroup(replacing: .appInfo)` block calls it from the application menu:

```swift
CommandGroup(replacing: .appInfo) {
    Button("About mcp-inator") { aboutController.show(...) }
}
```

## Phase Breakdown

### Phase 1: Foundation
- `AppModeManager` + `AppDelegate` + updated `mcp_inatorApp`
- On-launch activation policy applied from saved preference
- Switching modes works (dock icon appears/disappears, popover hides/shows)
- No windowed UI yet — dock mode shows a blank/placeholder window

### Phase 2: Main Window
- `AgentsView.swift` extracted from `MenuBarView`
- `MainWindowView` with `NavigationSplitView` wiring all three content views
- Window size/position persistence via SwiftUI scene ID
- Minimum window size enforced
- Toolbar with contextual Add Server action

### Phase 3: Preferences + Launch at Login
- `PreferencesView` with both toggles
- `Settings` scene wired to Cmd+,
- `SMAppService` Launch at Login implementation
- About menu item in dock mode via `CommandGroup`

### Phase 4: Polish & Edge Cases
- Off-screen window position recovery
- Mode toggle while sheet/modal open (dismiss first)
- Multiple rapid toggles stability
- Close window quits app (AppDelegate)
- Tests: `AppModeManagerTests`, update integration tests

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Activation policy | `NSApp.setActivationPolicy()` | Standard AppKit, works immediately at runtime |
| Scene switching | `if/else` in `@SceneBuilder` | SwiftUI native; no custom window management for scene lifecycle |
| Preferences window | SwiftUI `Settings` scene | Free Cmd+, wiring; macOS 13+ available |
| Launch at Login | `SMAppService.mainApp` | Modern macOS 13+ API; no helper bundle needed |
| Window frame persistence | SwiftUI `Window` scene ID | Automatic via AppKit frame autosave; no manual UserDefaults |
| Close → Quit | `NSApplicationDelegate` | Standard AppKit mechanism; clean integration via `@NSApplicationDelegateAdaptor` |
| AgentsTabView sharing | Extract to `AgentsView.swift` | Single source, used from both MenuBarView and MainWindowView |
