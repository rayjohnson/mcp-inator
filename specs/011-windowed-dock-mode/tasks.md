# Tasks: Windowed App Mode with Menu Bar Toggle

**Input**: Design documents from `specs/011-windowed-dock-mode/`

**Organization**: Tasks grouped by user story. US1 (Enable Dock Mode) is the MVP — complete it first and validate before moving to US2/US3.

---

## Phase 1: Setup

**Purpose**: Add framework dependency needed for Launch at Login.

- [ ] T001 Add `ServiceManagement` framework to mcp-inator target in `project.yml` and regenerate `mcp-inator.xcodeproj` via `xcodegen generate`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that all three user stories depend on. Must complete before any story work begins.

- [ ] T002 Create `AppModeManager` — `@MainActor final class AppModeManager: ObservableObject` with `@AppStorage("showInDock") private(set) var showInDock: Bool = false` and a stub `setShowInDock(_ enabled: Bool)` method in `mcp-inator/App/AppModeManager.swift`
- [ ] T003 [P] Create `AppDelegate` — `final class AppDelegate: NSObject, NSApplicationDelegate` implementing `applicationShouldTerminateAfterLastWindowClosed(_:)` that reads `UserDefaults.standard.bool(forKey: "showInDock")` in `mcp-inator/App/AppDelegate.swift`

**Checkpoint**: Foundation ready — user story implementation can begin.

---

## Phase 3: User Story 1 — Enable Dock Mode (Priority: P1) 🎯 MVP

**Goal**: Toggling "Show in Dock" on immediately gives the app a dock icon, removes the menu bar icon, and opens a main window — all without restart. Toggling off fully reverses.

**Independent Test**: Toggle "Show in Dock" on in the popover; verify dock icon appears, menu bar icon disappears, a resizable window opens. Toggle off; verify full reversal.

- [ ] T004 [US1] Wire `AppDelegate` and `AppModeManager` into `mcp_inatorApp`: add `@NSApplicationDelegateAdaptor(AppDelegate.self)` and `@StateObject private var appModeManager = AppModeManager()`; inject `appModeManager` into the environment in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T005 [US1] Add `if appModeManager.showInDock { Window(...) } else { MenuBarExtra { ... } }` conditional scene structure to `mcp_inatorApp.body`; the Window branch shows a placeholder `Text("mcp-inator")` for now in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T006 [P] [US1] Create stub `MainWindowView` — `struct MainWindowView: View` with `Text("mcp-inator").frame(minWidth: 800, minHeight: 500)` — in `mcp-inator/UI/MainWindowView.swift`
- [ ] T007 [US1] Implement `AppModeManager.setShowInDock(_ enabled: Bool)`: call `NSApp.setActivationPolicy(enabled ? .regular : .accessory)`, call `openMainWindow()` when enabling (use `NSApp.windows` to find or open by scene ID), and post a notification or set a flag when disabling so the window closes in `mcp-inator/App/AppModeManager.swift`
- [ ] T008 [US1] Update the Window scene branch in `mcp_inatorApp.body` to use `MainWindowView()` with `.defaultSize(width: 960, height: 620)`, and apply `.onAppear { NSApp.setActivationPolicy(.regular) }` on launch when `showInDock` is already true in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T009 [P] [US1] Create `PreferencesView` — `struct PreferencesView: View` containing a `Form` with a `Toggle("Show in Dock", ...)` wired to `AppModeManager.setShowInDock(_:)` — in `mcp-inator/UI/PreferencesView.swift`
- [ ] T010 [US1] Create `PreferencesWindowController` — `@MainActor final class PreferencesWindowController` mirroring the existing `AboutWindowController` pattern, hosting `PreferencesView` in an `NSWindow` — in `mcp-inator/App/mcp_inatorApp.swift` (below existing controllers)
- [ ] T011 [US1] Add `Settings { PreferencesView().environmentObject(appModeManager) }` scene to the dock-mode branch of `mcp_inatorApp.body` (wires Cmd+, automatically in dock mode) in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T012 [US1] Add "Preferences…" button to `MenuBarView` popover footer (alongside the existing About/Quit buttons) that opens `PreferencesWindowController`; inject the controller via environment or pass via init in `mcp-inator/UI/MenuBarView.swift`

**Checkpoint**: US1 complete — dock mode toggle works end-to-end. Menu bar and dock modes fully reversible.

---

## Phase 4: User Story 2 — Windowed Layout Navigation (Priority: P2)

**Goal**: The main window has a sidebar (Servers / Agents / Catalog), each section shows the correct content view, the window is resizable with a minimum size, size/position persists, Preferences window is reachable via Cmd+,, and About is in the application menu.

**Independent Test**: In dock mode, navigate all three sidebar sections, open Preferences via Cmd+,, resize the window, quit and relaunch — window reopens at the same size and position.

- [ ] T013 [US2] Extract `AgentsTabView` from its `private` scope inside `MenuBarView` into a new `internal struct AgentsView: View` in `mcp-inator/UI/AgentsView.swift`; update `MenuBarView` to reference `AgentsView()` in `mcp-inator/UI/MenuBarView.swift`
- [ ] T014 [US2] Implement full `MainWindowView` with `NavigationSplitView`: sidebar `List` with `Label("Servers", ...)`, `Label("Agents", ...)`, `Label("Catalog", ...)` rows; detail area switches on `selectedSection` enum showing `ConfigLibraryView()`, `AgentsView()`, or `CatalogView()` respectively; default selection is Servers in `mcp-inator/UI/MainWindowView.swift`
- [ ] T015 [P] [US2] Add contextual window toolbar to `MainWindowView`: show an "Add Server" `ToolbarItem` when the Servers section is selected (triggers the same add-server sheet that `ConfigLibraryView` uses) in `mcp-inator/UI/MainWindowView.swift`
- [ ] T016 [US2] Apply window constraints to the Window scene in `mcp_inatorApp.body`: `.defaultSize(width: 960, height: 620)`, `.windowResizability(.contentMinSize)`, and set `frame(minWidth: 800, minHeight: 500)` on `MainWindowView` to enforce the minimum size in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T017 [P] [US2] Add Launch at Login toggle to `PreferencesView`: import `ServiceManagement`; add `Toggle("Launch at Login", isOn: $launchAtLogin)` that calls `SMAppService.mainApp.register()` on enable and `SMAppService.mainApp.unregister()` on disable; read initial state from `SMAppService.mainApp.status == .enabled` in `mcp-inator/UI/PreferencesView.swift`
- [ ] T018 [US2] Add About application-menu command for dock mode: `CommandGroup(replacing: .appInfo) { Button("About mcp-inator") { aboutController.show(...) } }` in the dock-mode scene's `.commands { }` modifier in `mcp-inator/App/mcp_inatorApp.swift`

**Checkpoint**: US2 complete — full windowed layout working, Preferences accessible, Launch at Login functional.

---

## Phase 5: User Story 3 — Return to Menu Bar Mode (Priority: P3)

**Goal**: Toggling off fully reverts — dock icon gone, menu bar icon back, popover works — stable across multiple rapid toggles and modal-open edge cases.

**Independent Test**: With dock mode active, toggle it off five times in rapid succession; confirm no duplicate windows/icons, no crashes, and the popover opens correctly after each reversion.

- [ ] T019 [US3] Harden `AppModeManager.setShowInDock(false)`: close the main window explicitly before calling `NSApp.setActivationPolicy(.accessory)` to ensure the dock icon disappears cleanly; use `NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.close()` in `mcp-inator/App/AppModeManager.swift`
- [ ] T020 [US3] Guard against toggling during an active sheet: if `PreferencesView` is presented from within a sheet that is itself presented over active content, post an `AppModeManager.isTransitioning` flag that disables the toggle while a mode switch is in progress in `mcp-inator/App/AppModeManager.swift` and `mcp-inator/UI/PreferencesView.swift`

**Checkpoint**: US3 complete — toggle is fully reversible and stable under adversarial conditions.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T021 [P] Implement off-screen window recovery: after restoring window position, check if the window frame intersects any `NSScreen.screens` visible frame; if not, call `window.center()` on the primary screen in `mcp-inator/App/AppModeManager.swift` or within the `Window` scene's `onAppear`
- [ ] T022 [P] Add `AppModeManagerTests`: test that `setShowInDock(true)` sets `showInDock = true`, `setShowInDock(false)` sets it back, and that `UserDefaults` persists the value across `AppModeManager` re-initialization in `mcp-inatorTests/Unit/AppModeManagerTests.swift`
- [ ] T023 Run `make test` (must pass all 230+ tests) and `make lint` (no new violations); fix any issues

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — blocks all user stories
- **Phase 3 (US1)**: Depends on Phase 2 — MVP
- **Phase 4 (US2)**: Depends on Phase 3 (needs real MainWindowView stub from T006 and scene wiring from T008)
- **Phase 5 (US3)**: Can start after Phase 3 (hardening the same toggle logic)
- **Phase 6 (Polish)**: Depends on all story phases

### Within User Story 1

- T004 → T005 → T006 (parallel with T005) → T007 → T008
- T009 (parallel with T007) → T010 → T011 → T012

### Within User Story 2

- T013 (extract AgentsView) must complete before T014 (MainWindowView uses it)
- T014 → T015 (parallel), T016 (parallel), T017 (parallel)
- T018 independent of T013–T017

---

## Parallel Opportunities

### US1 Parallel Group
```
T006 (stub MainWindowView) || T009 (PreferencesView)
```

### US2 Parallel Group
```
T015 (toolbar) || T016 (window constraints) || T017 (Launch at Login)
```

### Polish Parallel Group
```
T021 (off-screen recovery) || T022 (AppModeManagerTests)
```

---

## Implementation Strategy

### MVP (US1 only — ~8 tasks)

1. Phase 1: T001
2. Phase 2: T002, T003
3. Phase 3: T004 → T005 → T006+T009 → T007 → T008 → T010 → T011 → T012
4. **Validate**: Toggle works, dock icon appears/disappears, window opens/closes, popover restored
5. Ship or demo as-is

### Full Delivery

1. MVP first (US1)
2. US2: sidebar layout + Preferences window + Launch at Login
3. US3: hardening + rapid-toggle stability
4. Polish: off-screen recovery, tests, lint

---

## Notes

- `[P]` = can run in parallel with other `[P]` tasks in the same phase (different files, no shared state dependencies)
- The `AboutWindowController` in `mcp_inatorApp.swift` is the exact pattern to follow for `PreferencesWindowController`
- `Settings` scene (Cmd+,) only exists in the dock-mode branch — this is intentional; Cmd+, has no target in menu bar mode
- Window frame persistence is automatic via the stable `id: "main"` on the `Window` scene — no manual `UserDefaults` needed
- `SMAppService` requires macOS 13+ — deployment target is already 13.0, so no `@available` guard needed
