# Tasks: In-App Help & README Overhaul

**Input**: Design documents from `specs/017-docs/`

**Feature**: Add a `HelpView` to the macOS app (reachable from the menu bar popover footer and the dock-mode Help menu) covering four topics: overview, server setup, catalog, and usage sharing. Overhaul `README.md` and add `CONTRIBUTING.md`.

**Key architectural decisions**:
- `HelpView` is a static SwiftUI `ScrollView` — no network calls, works offline
- `HelpWindowController` mirrors the existing `PreferencesWindowController` pattern
- Menu bar mode: "Help…" button in `MenuBarView` popover footer (alongside About + Preferences)
- Dock mode: `CommandGroup(after: .help)` entry in Application menu (alongside existing `replacing: .appInfo` and `replacing: .appSettings`)
- `openHelpWindow` environment key mirrors `openPreferencesWindow` pattern
- No new dependencies

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

**Purpose**: Create the `HelpWindowController` infrastructure and environment key before any story work.

- [ ] T001 Add `OpenHelpWindowKey` environment key to `mcp-inator/App/mcp_inatorApp.swift` following the existing `OpenPreferencesWindowKey` pattern (around line 381); add `openHelpWindow` computed property on `EnvironmentValues`
- [ ] T002 [P] Create `mcp-inator/UI/HelpView.swift`: a `ScrollView` with four `Section`-style `VStack` blocks (What is mcp-inator?, Adding and Configuring Servers, The Catalog, Usage Sharing) using the copy from `specs/017-docs/data-model.md`; no network calls, no state
- [ ] T003 [P] Create `HelpWindowController` class in `mcp-inator/App/mcp_inatorApp.swift` (or a new `mcp-inator/App/HelpWindowController.swift`): opens an `NSWindow` hosting `HelpView` via `NSHostingController`; mirrors the existing `PreferencesWindowController` structure; window title "mcp-inator Help"

**Checkpoint**: `HelpView` previews correctly in Xcode. `HelpWindowController` compiles.

---

## Phase 2: User Story 2 — In-App Help Entry Points (Priority: P2) 🎯

**Goal**: Users can open the help window from both menu bar mode and dock mode.

**Independent Test**: Quickstart Scenario 1 (menu bar mode) + Scenario 2 (dock mode) — Help window opens and shows all four sections; closes and reopens without error; works with Wi-Fi off.

- [ ] T004 [US2] Wire `HelpWindowController` into `mcp-inator/App/mcp_inatorApp.swift`: instantiate alongside `AboutWindowController` and `PreferencesWindowController`; inject `openHelpWindow` into the environment on `MenuBarExtra` (around line 66 where `openAboutWindow` and `openPreferencesWindow` are set)
- [ ] T005 [US2] Add "Help…" button to the `MenuBarView` footer in `mcp-inator/UI/MenuBarView.swift`: insert between "About mcp-inator…" and "Preferences…" (around line 49); use `@Environment(\.openHelpWindow)` following the existing About/Preferences pattern
- [ ] T006 [US2] Add Help entry to the Application menu (dock mode) in `mcp-inator/App/mcp_inatorApp.swift`: add `CommandGroup(after: .help) { Button("mcp-inator Help…") { openHelpWindow() } }` alongside the existing `replacing: .appInfo` and `replacing: .appSettings` groups
- [ ] T007 [US2] Update "Contributing Usage Data" section in `mcp-inator/UI/PreferencesView.swift`: add a 2–3 sentence inline description of what is and isn't shared (matching the Usage Sharing section of `HelpView`) above both the opted-in and not-opted-in states

**Checkpoint**: App builds and runs. Help window opens from popover footer. Help window opens from Application → Help menu (dock mode). Preferences shows inline copy. All content displays with Wi-Fi off.

---

## Phase 3: User Story 1 — README Overhaul (Priority: P1)

**Goal**: A new user landing on the GitHub repo can understand what the app does, install it, and get started within the README alone.

**Independent Test**: Quickstart Scenario 4 — README renders correctly in a Markdown previewer; all five sections present; Quick Start has ≤ 3 steps; Privacy section present and accurate.

- [ ] T008 [P] [US1] Capture new screenshots: menu bar popover (server list visible) and catalog view; save as `docs/images/menubar-v0.5.0.png` and `docs/images/catalog-v0.5.0.png`
- [ ] T009 [US1] Rewrite `README.md` with sections per `specs/017-docs/data-model.md`: Hero (1-sentence description + screenshot), Installation (preserve existing, polish), Quick Start (launch → add server → apply to agent, ≤ 3 steps), Features (server management, catalog, agent matrix, usage sharing opt-in), Privacy (3–4 sentences, accurate to what `UsageSharingService` sends), Contributing (1 line linking to `CONTRIBUTING.md`)

**Checkpoint**: `README.md` renders on GitHub with all sections. New-user test passes per SC-001.

---

## Phase 4: User Story 3 — Contributing Guide (Priority: P3)

**Goal**: A developer can build the app from source and open a PR using only `CONTRIBUTING.md`.

**Independent Test**: Quickstart Scenario 5 — `CONTRIBUTING.md` renders on GitHub; a developer following it can build the app and knows the full PR checklist.

- [ ] T010 [US3] Create `CONTRIBUTING.md` at repo root with sections per `specs/017-docs/data-model.md`: Prerequisites (Xcode version, `swiftlint` via Homebrew, `make`), Build (`xcodebuild` command + DerivedData path), Run (kill + launch command), Test & Lint (`make test`, `make lint`, `make cover`), Before Every PR (checklist mirroring `CLAUDE.md`: lint clean, tests pass, VERSION bump, RELEASE_NOTES.md), Opening a PR (branch naming `feature/NNN-name`, PR description)

**Checkpoint**: `CONTRIBUTING.md` renders on GitHub. PR checklist matches `CLAUDE.md`.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T011 Run `make lint` and fix all SwiftLint warnings in `HelpView.swift`, `HelpWindowController`, and any updated files (`MenuBarView.swift`, `PreferencesView.swift`, `mcp_inatorApp.swift`)
- [ ] T012 Run `make cover` — verify tests pass and coverage threshold is met
- [ ] T013 [P] Bump patch version in `VERSION`
- [ ] T014 [P] Update `RELEASE_NOTES.md`: add entry for in-app help view and README/CONTRIBUTING overhaul
- [ ] T015 Run all five quickstart.md scenarios to confirm the full feature works

**Checkpoint**: PR ready — lint clean, tests green, coverage above threshold, version bumped.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T002 and T003 can run in parallel
- **US2 (Phase 2)**: Requires Phase 1 complete (needs `HelpWindowController` + environment key); T004–T007 are sequential after T001; T005 and T006 can run in parallel after T004
- **US1 (Phase 3)**: Independent of US2 — T008 and T009 can overlap; T009 depends on T008 for screenshot paths
- **US3 (Phase 4)**: Independent of US1 and US2
- **Polish (Phase 5)**: Requires all implementation phases complete; T013 and T014 are parallel

### Parallel Opportunities

```bash
# Phase 1 — run together:
T002: HelpView.swift (content)
T003: HelpWindowController (window infrastructure)

# Phase 2 — after T004:
T005: MenuBarView "Help…" button
T006: CommandGroup Help menu entry

# Phase 3 — run together:
T008: Capture screenshots
T009: Write README (can draft without final screenshots, insert at end)

# Phase 5 — run together:
T013: Bump VERSION
T014: Update RELEASE_NOTES.md
```

---

## Implementation Strategy

### MVP (US2 Only — Phases 1–2)

1. Complete Phase 1: Setup (T001–T003)
2. Complete Phase 2: US2 entry points (T004–T007)
3. **STOP and VALIDATE**: Help window opens from both modes, offline, all four sections visible
4. Ship — app users get in-context help immediately

### Full Delivery Order

1. Phase 1 (Setup) → Phase 2 (US2 in-app help) — highest user value
2. Phase 3 (US1 README) — new user experience
3. Phase 4 (US3 Contributing guide) — developer experience
4. Phase 5 (Polish)

---

## Task Summary

| Phase | Tasks | Count |
|-------|-------|-------|
| Phase 1: Setup | T001–T003 | 3 |
| Phase 2: US2 (In-App Help) | T004–T007 | 4 |
| Phase 3: US1 (README) | T008–T009 | 2 |
| Phase 4: US3 (Contributing) | T010 | 1 |
| Phase 5: Polish | T011–T015 | 5 |
| **Total** | | **15** |

**Parallel opportunities**: 6 tasks marked [P]
**MVP scope**: Phases 1–2 (7 tasks) — in-app help live, no README changes yet
