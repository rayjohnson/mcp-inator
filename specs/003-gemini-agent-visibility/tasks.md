# Tasks: Gemini Desktop Support + Agent Visibility Controls

**Branch**: `003-gemini-agent-visibility` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

**Input**: Design documents from `specs/003-gemini-agent-visibility/`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no incomplete dependencies)
- **[Story]**: Which user story this task belongs to
- Exact file paths included in all descriptions

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Protocol extension + model changes + migration — both user stories depend on all of these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T001 Add `var isAppManaged: Bool { false }` as a protocol extension default on `AgentAdapter` in `mcp-inator/Adapters/AgentAdapter.swift` (add an `extension AgentAdapter` block below the protocol definition returning `false`; no existing conformances need changes)
- [X] T002 In `mcp-inator/Models/AgentRecord.swift`: (a) add `.geminiDesktop = "gemini_desktop"` to `AgentType` with `displayName = "Gemini Desktop"` and `defaultConfigPath = "\(home)/Library/Application Support/Google/Gemini/mcp_servers.json"`; (b) add `var isVisible: Bool` field to `AgentRecord` struct; (c) add `isVisible = true` to the `init(agentType:configPath:)` convenience initializer; (d) add `isVisible = (row["isVisible"] as Int) != 0` to `init(row:)`; (e) add `container["isVisible"] = isVisible ? 1 : 0` to `encode(to:)`
- [X] T003 Create `mcp-inator/Store/Migrations/Migration004.swift` with migration key `"004_agent_visibility"` running `ALTER TABLE agents ADD COLUMN isVisible INTEGER NOT NULL DEFAULT 1`; register `Migration004` in `mcp-inator/Store/ConfigStore.swift` (add `.register(in: &migrator)` call after `Migration003`); wire `Migration004.swift` into `mcp-inator.xcodeproj/project.pbxproj` (PBXFileReference + PBXBuildFile + app Sources build phase + Migrations group membership, same pattern as `Migration003.swift`)

**Checkpoint**: App compiles with new `AgentType.geminiDesktop` case, `AgentRecord.isVisible`, and migration registered. `make build` succeeds.

---

## Phase 2: User Story 1 — Gemini Desktop Appears as a Detected Agent (Priority: P1) 🎯

**Goal**: Gemini Desktop shows in the Agents tab when `/Applications/Gemini.app` is installed. Tapping it shows an "in-app managed" banner explaining mcp-inator cannot configure its MCP servers.

**Independent Test**: With `/Applications/Gemini.app` installed, launch mcp-inator → Agents tab → "Gemini Desktop" row present → tap → in-app managed banner shown (not "config file not accessible") → no toggle list.

- [X] T004 [US1] Create `mcp-inator/Adapters/GeminiDesktopAdapter.swift`: `struct GeminiDesktopAdapter: AgentAdapter` with `agentType = .geminiDesktop`, `displayName = "Gemini Desktop"`, `isAppManaged = true`; `defaultConfigPath()` returns `~/Library/Application Support/Google/Gemini/mcp_servers.json`; `isInstalled()` checks `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") != nil` OR `FileManager.default.fileExists(atPath: "/Applications/Gemini.app")`; `readConfigs(from:)` returns `[:]`; `writeConfigs(...)` returns `.success`; `removeConfig(...)` returns `.success`; `validateServerKey(_:)` returns `.valid`; wire into `project.pbxproj` (PBXFileReference + PBXBuildFile + app Sources build phase + Adapters group)
- [X] T005 [P] [US1] In `mcp-inator/UI/AgentListView.swift`: (a) add `.geminiDesktop: GeminiDesktopAdapter()` to the `private var adapter` switch; (b) add an `isAppManaged` banner branch at the top of the conditional content in `body` — before the `!agent.isAvailable` check — showing a banner with `Image(systemName: "info.circle.fill")` and text `"Gemini Desktop manages MCP servers internally. Add servers directly in the Gemini app settings."` with no "Change Path" button and no toggle list
- [X] T006 [P] [US1] In `mcp-inator/UI/AgentIcon.swift`: add `.geminiDesktop` case that loads the real Gemini app icon via `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS")` → `NSWorkspace.shared.icon(forFile: url.path)` with a blue `LetterBadge(letter: "G", background: Color(red: 0.26, green: 0.52, blue: 0.96))` fallback; extract a `GeminiDesktopAppIcon` private struct mirroring the `ClaudeAppIcon` pattern
- [X] T007 [P] [US1] In `mcp-inator/UI/DiscoveryView.swift`: add `.geminiDesktop: GeminiDesktopAdapter()` to the `private let adapters` dictionary
- [X] T008 [P] [US1] In `mcp-inator/UI/MenuBarView.swift`: add `GeminiDesktopAdapter()` to the `allAdapters` computed property
- [X] T009 [P] [US1] In `mcp-inator/App/mcp_inatorApp.swift`: add `GeminiDesktopAdapter()` to the adapters array passed to the agent discovery scan

**Checkpoint**: Build succeeds. With Gemini.app installed, Agents tab shows a "Gemini Desktop" row. Tapping it shows the in-app banner. No crash when `.geminiDesktop` is encountered anywhere. DiscoveryView includes Gemini Desktop in "New Agents Found".

---

## Phase 3: User Story 2 — Hide Agents You Don't Use (Priority: P1)

**Goal**: Users can hide any agent from the Agents tab and Servers tab badges via a Manage Agents screen. Hiding is non-destructive and immediately reflected everywhere including PropagationView.

**Independent Test**: With 5 agents shown, hide "Codex CLI" via Manage Agents → Agents tab no longer shows Codex CLI row → Servers tab badges no longer show Codex CLI → PropagationView does not list Codex CLI → re-enable via Manage → everything restored immediately.

- [X] T010 [US2] In `mcp-inator/Store/ConfigStore.swift`: (a) add `var visibleAgents: [AgentRecord] { agents.filter(\.isVisible) }` computed property; (b) add `func setAgentVisibility(agentId: Int64, visible: Bool) throws` that updates `isVisible` in the `agents` table using GRDB and then refreshes `agents` from the DB; (c) update `fetchStatusMatrix()` to filter to only agents where `isVisible = 1` so hidden agents produce no badge columns (add `WHERE isVisible = 1` to the agents query or filter in Swift after fetch)
- [X] T011 [P] [US2] Create `mcp-inator/UI/ManageAgentsView.swift`: a `NavigationStack`-pushed view with `navigationTitle("Manage Agents")`; a `List` using `store.agents` (all agents, not filtered); each row shows `AgentIcon` (24×24, clipped), `agent.displayName`, availability indicator (`checkmark.circle.fill` green if `isAvailable`), and a `Toggle` bound to `agent.isVisible` with label "Visible" (hidden via `labelsHidden()`); toggle action calls `try? store.setAgentVisibility(agentId: agent.id!, visible: newValue)`; wire into `project.pbxproj` (PBXFileReference + PBXBuildFile + app Sources build phase + UI group)
- [X] T012 [US2] In `mcp-inator/UI/MenuBarView.swift` (`AgentsTabView`): (a) change `List(store.agents)` to `List(store.visibleAgents)`; (b) add empty state overlay when `store.visibleAgents.isEmpty` with text `"All agents are hidden."` and a `Button("Manage") { showManage = true }` link; (c) add `@State private var showManage = false` and `.navigationDestination(isPresented: $showManage) { ManageAgentsView().environmentObject(store) }`; (d) add `.toolbar { ToolbarItem(placement: .primaryAction) { Button { showManage = true } label: { Image(systemName: "slider.horizontal.3") }.help("Manage agent visibility") } }` to `AgentsTabView`
- [X] T013 [P] [US2] In `mcp-inator/UI/PropagationView.swift`: (a) update `loadAgents()` to filter `enabledAgents` to only visible agents — change `store.findEnabledAgents(for: config.uuid)` result to intersect with `store.visibleAgents` (keep only agents where `isVisible == true`); (b) add `.geminiDesktop: GeminiDesktopAdapter()` to the `private let adapters` dictionary (required now that `.geminiDesktop` is a valid `AgentType`)

**Checkpoint**: Hiding an agent removes it from the Agents list and Servers badges immediately. PropagationView omits hidden agents. Manage Agents shows all 5 agents with toggles. Unhiding restores everything.

---

## Phase 4: Tests

**Purpose**: Unit tests for the new adapter and visibility store methods.

- [X] T014 [P] Create `mcp-inatorTests/Unit/GeminiDesktopAdapterTests.swift`: test `isInstalled()` returns `true` when `Gemini.app` is at `/Applications/Gemini.app`; test `readConfigs(from:)` returns empty dict without throwing; test `writeConfigs(...)` returns `.success` without writing any file; test `removeConfig(...)` returns `.success` without writing any file; test `isAppManaged == true`; wire into `project.pbxproj` (PBXFileReference + PBXBuildFile + test Sources build phase + Unit group)
- [X] T015 [P] Create `mcp-inatorTests/Unit/AgentVisibilityTests.swift`: test `setAgentVisibility(agentId:visible:false)` persists `isVisible = false` to DB and `agents` refreshes; test `visibleAgents` filters out records where `isVisible == false`; test `visibleAgents` includes records where `isVisible == true`; test round-trip hide → unhide restores agent to visible list; wire into `project.pbxproj` (same pattern as other Unit tests)

**Checkpoint**: `make test` passes with all new test cases green.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T016 Build and launch the app; confirm `AgentIcon` for `.geminiDesktop` loads the real Gemini app icon from `NSWorkspace` (not the fallback "G" badge); confirm the "Gemini Desktop" row appears in the Agents tab
- [ ] T017 Confirm the DiscoveryView "New Agents Found" flow includes Gemini Desktop when first launching with the app installed; confirm no crash if Gemini Desktop is not installed
- [X] T018 Run `make test` end-to-end; fix any compilation errors or test failures introduced by the new `.geminiDesktop` case in exhaustive switches
- [ ] T019 Manual end-to-end: hide two agents via Manage Agents → confirm Servers tab badge columns reduced → confirm hidden agents absent from PropagationView → unhide → confirm full restoration; update `specs/003-gemini-agent-visibility/quickstart.md` for any divergence

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — start immediately
  - T001, T002 are parallel (different files)
  - T003 depends on T002 (needs `.geminiDesktop` in `AgentType` to exist in the migration file context, though SQLite ALTER is independent — safe to run parallel; register in ConfigStore is a sequential edit)
- **Phase 2 (US1)**: Requires Phase 1 complete
  - T004 first (creates `GeminiDesktopAdapter` type)
  - T005, T006, T007, T008, T009 all parallel after T004 (different files, only depend on T004)
- **Phase 3 (US2)**: Requires Phase 2 complete (T008 edits `MenuBarView.swift`; T012 also edits `MenuBarView.swift` — must not overlap)
  - T010 and T011 parallel (different files)
  - T012 requires T010 + T011 (uses `visibleAgents` + navigates to ManageAgentsView)
  - T013 parallel with T012 (different file), requires T010
- **Phase 4 (Tests)**: T014 and T015 parallel; can run after Phase 1 for T015, after Phase 2 for T014
- **Phase 5 (Polish)**: Requires Phases 2, 3, 4 complete

### Parallel Opportunities

```
Phase 1:  T001 ║ T002 → T003

Phase 2:  T004 → T005 ║ T006 ║ T007 ║ T008 ║ T009

Phase 3:  T010 ║ T011 → T012
                       T010 → T013 (parallel with T012)

Phase 4:  T014 ║ T015

Phase 5:  T016 → T017 → T018 → T019
```

---

## Implementation Strategy

### MVP: Both Stories Together (both P1)

1. Complete Phase 1: Foundational ← **blocks everything**
2. Complete Phase 2: US1 — Gemini Desktop detection
3. Validate US1: Launch app → Agents tab → Gemini Desktop row → in-app banner
4. Complete Phase 3: US2 — Agent visibility controls
5. Validate US2: Hide/unhide agent → badges + list update correctly
6. Complete Phase 4: Tests (`make test` green)
7. Complete Phase 5: Polish + manual end-to-end

---

## Notes

- `[P]` = different files, no incomplete dependencies — safe to implement in parallel
- All new Swift files require `project.pbxproj` wiring (PBXFileReference + PBXBuildFile + build phase + group) — each task that creates a new file includes this step
- `GeminiDesktopAdapter` is intentionally a no-op for reads/writes — this is by design, not an incomplete implementation
- `store.agents` remains the full `@Published` array; `store.visibleAgents` is a computed filter — `ManageAgentsView` always uses `store.agents`, never `store.visibleAgents`
- T012 and T008 both edit `MenuBarView.swift` — they are in different phases and must not be worked on simultaneously
