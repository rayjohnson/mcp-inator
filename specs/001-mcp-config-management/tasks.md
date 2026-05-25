# Tasks: MCP Server Configuration Management

**Input**: Design documents from `specs/001-mcp-config-management/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/AgentAdapter.md ✅

**Tests**: Integration tests for all adapters are contractually required (contracts/AgentAdapter.md).
Unit tests are included for server-key transforms and sensitive-field heuristics. No TDD approach
for UI tasks.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no in-flight dependencies)
- **[Story]**: User story this task belongs to (US1–US7)
- Exact file paths are relative to the Xcode project root (`mcp-inator/`)

---

## Phase 1: Setup

**Purpose**: Create the Xcode project, wire up dependencies, and establish the build target.

- [ ] T001 Create Xcode project: macOS App, SwiftUI lifecycle, bundle ID `io.moov.mcp-inator`, deployment target macOS 13.0, in `mcp-inator/mcp-inator.xcodeproj`
- [ ] T002 Add Swift Package dependencies via SPM: GRDB.swift 6.x, Sparkle 2.x, TOMLKit (latest) in `mcp-inator/mcp-inator.xcodeproj`
- [ ] T003 [P] Create app target directory structure per plan.md: `mcp-inator/App/`, `mcp-inator/UI/`, `mcp-inator/Models/`, `mcp-inator/Store/`, `mcp-inator/Store/Migrations/`, `mcp-inator/Adapters/`
- [ ] T004 [P] Create test target directory structure: `mcp-inatorTests/Unit/`, `mcp-inatorTests/Integration/`, `mcp-inatorTests/Integration/Fixtures/`
- [ ] T005 [P] Configure Hardened Runtime entitlements: enable Hardened Runtime in build settings, add `.entitlements` file with `com.apple.security.get-task-allow = false` in `mcp-inator/Resources/mcp-inator.entitlements`

**Checkpoint**: Project builds (empty app) with all SPM packages resolved.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models, database layer, adapter protocol, all four concrete adapters, and the app
shell. Nothing user-visible works until this phase is complete.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Core Models

- [ ] T006 Implement `MCPServerConfig` + `EnvVar` structs (Codable, FetchableRecord, PersistableRecord, Identifiable; args/envVars stored as JSON TEXT; uuid as TEXT) in `mcp-inator/Models/MCPServerConfig.swift`
- [ ] T007 [P] Implement `AgentRecord` + `AgentType` enum + `AssignmentState` enum in `mcp-inator/Models/AgentRecord.swift`
- [ ] T008 Implement `ConfigAgentAssignment` struct (with `lastWrittenSnapshot: MCPServerConfig?` stored as JSON TEXT) in `mcp-inator/Models/ConfigAgentAssignment.swift`

### Database Layer

- [ ] T009 Implement Migration 001 SQL schema (mcp_server_configs, agents, config_agent_assignments tables + indexes per data-model.md) in `mcp-inator/Store/Migrations/Migration001.swift`
- [ ] T010 Implement `ConfigStore`: open GRDB DatabasePool at `~/Library/Application Support/mcp-inator/mcp-inator.db`, register and run DatabaseMigrator, expose db handle in `mcp-inator/Store/ConfigStore.swift`
- [ ] T011 Add `ConfigStore` CRUD for `MCPServerConfig`: `insert`, `update`, `delete` (cascade to assignments), `fetchAll`, `fetch(byUUID:)` in `mcp-inator/Store/ConfigStore.swift`
- [ ] T012 Add `ConfigStore` CRUD for `AgentRecord` and `ConfigAgentAssignment`: `upsertAgent`, `fetchAllAgents`, `setAssignmentState`, `fetchAssignment(configUUID:agentId:)`, `fetchEnabledConfigs(for:)` in `mcp-inator/Store/ConfigStore.swift`
- [ ] T013 [P] Unit test ConfigStore CRUD (insert/fetch/delete round-trips, cascade delete, assignment state transitions) in `mcp-inatorTests/Unit/ConfigStoreTests.swift`

### Adapter Protocol

- [ ] T014 Implement `AgentAdapter` protocol, `WriteResult`, `KeyValidationResult`, `AdapterError` per contracts/AgentAdapter.md in `mcp-inator/Adapters/AgentAdapter.swift`

### Integration Test Fixtures

- [ ] T015 [P] Create fixture files with realistic multi-entry configs: `claude_code_config.json`, `claude_desktop_config.json`, `gemini_config.json`, `codex_config.toml` in `mcp-inatorTests/Integration/Fixtures/`

### Concrete Adapters (T016–T019 parallelizable after T014 + T015)

- [ ] T016 [P] Implement `ClaudeCodeAdapter` (JSON, `~/.claude.json`, `mcpServers` key, reject `workspace` key, preserve non-mcpServers keys, atomic write, pre-flight on managed keys only) + all integration tests from contracts/AgentAdapter.md in `mcp-inator/Adapters/ClaudeCodeAdapter.swift` + `mcp-inatorTests/Integration/ClaudeCodeAdapterTests.swift`
- [ ] T017 [P] Implement `ClaudeDesktopAdapter` (JSON, `~/Library/Application Support/Claude/claude_desktop_config.json`, `mcpServers` key, preserve unrelated keys, atomic write, pre-flight on managed keys only) + all integration tests in `mcp-inator/Adapters/ClaudeDesktopAdapter.swift` + `mcp-inatorTests/Integration/ClaudeDesktopAdapterTests.swift`
- [ ] T018 [P] Implement `GeminiCLIAdapter` (JSON, `~/.gemini/settings.json`, `mcpServers` key, reject `_` in server keys, preserve unrelated keys, atomic write, pre-flight on managed keys only) + all integration tests in `mcp-inator/Adapters/GeminiCLIAdapter.swift` + `mcp-inatorTests/Integration/GeminiCLIAdapterTests.swift`
- [ ] T019 Implement `CodexCLIAdapter` (TOML via TOMLKit, `~/.codex/config.toml`, `mcp_servers` section, preserve all non-mcp_servers TOML keys, atomic write, pre-flight on managed keys only) + all integration tests in `mcp-inator/Adapters/CodexCLIAdapter.swift` + `mcp-inatorTests/Integration/CodexCLIAdapterTests.swift`

### App Shell

- [ ] T020 Implement `mcp_inatorApp` (@main, `NSStatusItem` setup, popover lifecycle, icon in menu bar) in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T021 Implement `MenuBarView` shell (root popover SwiftUI view, placeholder content, navigation structure) in `mcp-inator/UI/MenuBarView.swift`

**Checkpoint**: All four adapters pass their integration test suites. App launches and shows a
menubar icon with an empty popover. Database initializes correctly.

---

## Phase 3: User Story 1 — Add MCP Server Config (Priority: P1) 🎯 MVP

**Goal**: Users can add, edit, and delete configs in the mcp-inator library. No agent writes yet.
The config library is the single source of truth; this phase makes it usable.

**Independent Test**: Launch mcp-inator → add a new entry with display name "GitHub MCP", command
`npx`, arg `@modelcontextprotocol/server-github`, env var `GITHUB_TOKEN=ghp_xxxx` → verify entry
appears in the list with server key `github-mcp` and env var value is masked → edit it → delete it
with confirmation → library is empty. No agent integration needed.

- [ ] T022 Implement server key auto-population transform (`displayName` → lowercase → spaces to hyphens → strip non-`[a-z0-9-]`) in `mcp-inator/Models/MCPServerConfig.swift`
- [ ] T023 [P] Unit test server key transform (basic cases, edge cases: leading/trailing spaces, unicode, already-valid key, reserved-word passthrough) in `mcp-inatorTests/Unit/ServerKeyTransformTests.swift`
- [ ] T024 [P] Implement `EnvVar.isSensitive` heuristic (literal values = sensitive by default; values matching `^\$\{[A-Z_][A-Z0-9_]*\}$` = not sensitive; user-overridable flag) in `mcp-inator/Models/MCPServerConfig.swift`
- [ ] T025 [P] Unit test sensitive field heuristic (literal string, `${VAR}` reference, lowercase `${var}` reference, empty value) in `mcp-inatorTests/Unit/SensitiveFieldTests.swift`
- [ ] T026 [US1] Implement `AddEditConfigView`: form fields for displayName, serverKey (auto-populated, editable), command, args (dynamic list), envVars (key/value/sensitive pairs with `••••` masking and per-field reveal toggle FR-016), validation errors inline, Save/Cancel in `mcp-inator/UI/AddEditConfigView.swift`
- [ ] T027 [P] [US1] Implement `ConfigLibraryView`: scrollable list of configs, actionable empty state ("Add your first MCP server" CTA, FR-029), delete swipe action with confirmation prompt (FR-004) in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T028 [US1] Wire `ConfigLibraryView` ↔ `AddEditConfigView` (add button opens form, tap-to-edit, delete confirmation cascade) and connect both to `ConfigStore` in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T029 [US1] Connect `MenuBarView` to show `ConfigLibraryView` as root content; wire `ConfigStore` as environment object in `mcp-inator/UI/MenuBarView.swift` + `mcp-inator/App/mcp_inatorApp.swift`

**Checkpoint**: User can add, edit, delete configs in the library. Server key auto-populates.
Sensitive values are masked. Empty state shows correct CTA. No agent writes yet.

---

## Phase 4: User Story 5 — First-Run Agent Discovery (Priority: P1)

**Goal**: On first launch, the app discovers installed agents and offers per-entry import.
On subsequent launches, only newly installed agents are offered. Nothing is auto-applied.

**Independent Test**: Pre-install Claude Code CLI with two MCP entries in `~/.claude.json`.
Launch mcp-inator fresh (empty DB). Discovery screen appears listing Claude Code. Choose to
import → ImportReviewView shows the two entries as "new". Import one, skip one. Library has
one entry, agent file unchanged. Quit and relaunch → no discovery screen (agent already known).

- [ ] T030 [US5] Implement `ConfigStore.discoverAgents()`: iterate `AgentType.allCases`, call `adapter.isInstalled()`, upsert `AgentRecord` for found agents (set `isAvailable`), return list of newly discovered agents (not previously in `agents` table) in `mcp-inator/Store/ConfigStore.swift`
- [ ] T031 [US5] Implement first-run detection: check if `agents` table is empty at launch → call `discoverAgents()` → present `DiscoveryView` in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T032 [US5] Implement new-agent detection on subsequent launches (FR-019): after first run, check each `AgentType` not yet in `agents` table → if found, offer discovery-import for that agent only in `mcp-inator/App/mcp_inatorApp.swift`
- [ ] T033 [US5] Implement `DiscoveryView`: list of found/not-found agents, per-agent "Import" button, "Skip" option, empty state message when no agents found with link to path-override (FR-029 + FR-013) in `mcp-inator/UI/DiscoveryView.swift`
- [ ] T034 [US5] Implement `ImportReviewView`: three-category display (new entries with import/skip, exact matches shown as "already in library", conflicts with side-by-side diff and keep-library/use-agent/skip choice), per-entry decisions, confirm button writes only approved entries to `ConfigStore` (FR-025) in `mcp-inator/UI/ImportReviewView.swift`
- [ ] T035 [US5] Implement `ConfigStore.categorizeImport(from:agentId:)`: read adapter entries, compare against library, return `[ImportEntry]` with `.new`, `.exactMatch`, `.conflict(library:onDisk:)` categories in `mcp-inator/Store/ConfigStore.swift`

**Checkpoint**: On fresh launch, app scans for agents and shows discovery screen. Per-entry
import UI works with all three categories. Relaunching does not re-trigger discovery for
known agents. Declining import leaves files untouched.

---

## Phase 5: User Story 2 — Apply Config to an AI Agent (Priority: P1)

**Goal**: Users can enable and disable stored configs for specific agents. Writes are atomic,
pre-flight checked, and followed by restart notifications. Unavailable agents are distinguished
from disabled ones.

**Independent Test**: With "GitHub MCP" in library, open agent view for Claude Code → enable it
→ verify `~/.claude.json` has `github-mcp` entry → verify restart notification appears → disable
it → verify entry removed from file → config still in library. Simulate file edited externally →
attempt re-enable → drift diff is shown before write proceeds.

- [ ] T036 [US2] Add `ConfigStore.enableConfig(uuid:agentId:)`: validate server key via adapter, check FR-024 conflict, build full enabled-config set, call `adapter.writeConfigs(_:to:expectedExisting:)` using `lastWrittenSnapshot` from existing assignments, update `ConfigAgentAssignment` state + `lastWrittenSnapshot` on success in `mcp-inator/Store/ConfigStore.swift`
- [ ] T037 [US2] Add `ConfigStore.disableConfig(uuid:agentId:)`: call `adapter.removeConfig(key:from:expectedValue:)` using `lastWrittenSnapshot`, update assignment state (clear `lastWrittenSnapshot`) on success in `mcp-inator/Store/ConfigStore.swift`
- [ ] T038 [US2] Implement drift-detection flow: on `WriteResult.driftDetected`, present a diff confirmation sheet (on-disk vs. expected values); user must confirm before a forced write proceeds; forced write passes `nil` for `expectedExisting` in `mcp-inator/UI/AgentListView.swift`
- [ ] T039 [US2] Implement conflict-detection flow (FR-024): if `enableConfig` detects an existing on-disk key not written by mcp-inator, present both values and require user to choose before writing in `mcp-inator/UI/AgentListView.swift`
- [ ] T040 [US2] Implement `AgentListView`: per-agent list of all library configs, enable/disable toggle per config, "unavailable" badge (distinct from disabled) for inaccessible agents (FR-014), agent display name + config path in `mcp-inator/UI/AgentListView.swift`
- [ ] T041 [US2] Implement restart notification (FR-022): consolidated per-agent sheet/alert after successful write; for Gemini include "(or run `/mcp reload` in an active session)" in `mcp-inator/UI/AgentListView.swift`
- [ ] T042 [US2] Implement agent path-override prompt (FR-021 + FR-013): when agent is unavailable, show explanation + path browse/enter sheet; persist `isCustomPath = true` and new path to `AgentRecord` in `mcp-inator/UI/AgentListView.swift`
- [ ] T043 [US2] Implement availability refresh: call `ConfigStore.refreshAvailability()` (update `AgentRecord.isAvailable` for all agents) on popover open and before any write in `mcp-inator/Store/ConfigStore.swift` + `mcp-inator/UI/MenuBarView.swift`
- [ ] T044 [US2] Wire `AgentListView` into navigation: accessible from `MenuBarView` and from individual config entries in `ConfigLibraryView` in `mcp-inator/UI/MenuBarView.swift`
- [ ] T045 [US2] Implement error message surface (FR-012): all `AdapterError.writeFailure` cases produce specific, user-readable messages with file path and cause (not generic "failed") in `mcp-inator/UI/AgentListView.swift`

**Checkpoint**: Enabling a config writes the correct entry to the agent file. Disabling removes
it. Pre-flight drift detection presents a diff. Restart notification fires after every write.
Unavailable agents show their own state with a path-fix prompt.

---

## Phase 6: User Story 3 — Bulk Apply Configs to a New Agent (Priority: P2)

**Goal**: Users can apply a selection (or all) stored configs to a newly added agent in one
operation with a single consolidated restart notification.

**Independent Test**: With 3 configs in library (none applied to Gemini), open Gemini agent view
→ "Apply all" → pre-flight runs per config → conflict check runs → all write → single Gemini
restart notification. Verify `~/.gemini/settings.json` has all 3 entries.

- [ ] T046 [US3] Implement `ConfigStore.bulkEnableConfigs(uuids:agentId:)`: iterate selected configs, validate + write each (using enable flow from T036), collect errors per config, return aggregate result; on completion fire single consolidated restart notification in `mcp-inator/Store/ConfigStore.swift`
- [ ] T047 [US3] Add bulk-apply UI to `AgentListView`: multi-select mode or "Apply all" action, show per-config conflict/drift inline during bulk operation, confirm before writing in `mcp-inator/UI/AgentListView.swift`
- [ ] T048 [US3] Handle partial-success in bulk apply: if some configs succeed and others fail/conflict, show summary of what was applied and what was skipped with reasons in `mcp-inator/UI/AgentListView.swift`

**Checkpoint**: Bulk-apply writes selected configs to the agent file with one restart prompt.
Partial failures are surfaced per-config without aborting the whole operation.

---

## Phase 7: User Story 6 — Propagate Config Edits to Enabled Agents (Priority: P2)

**Goal**: After editing a config, users are immediately offered the chance to push the update
to all enabled agents with a before/after diff. Declining is safe — the pre-flight check will
catch it on the next write.

**Independent Test**: Enable "GitHub MCP" for Claude Code and Gemini. Edit the token value.
Save. PropagationView appears listing both agents with diffs. Accept. Both files updated.
Quit without accepting → files unchanged → re-open agent view and attempt any write → drift
detected, diff shown.

- [ ] T049 [US6] Implement `ConfigStore.findEnabledAgentsForConfig(uuid:)`: returns `[AgentRecord]` where assignment state is enabled for the given config in `mcp-inator/Store/ConfigStore.swift`
- [ ] T050 [US6] Implement `PropagationView`: per-agent diff preview (old value from `lastWrittenSnapshot` vs. new DB value), confirm/decline, on confirm calls `enableConfig` flow for each agent (uses drift detection naturally), consolidated restart notification in `mcp-inator/UI/PropagationView.swift`
- [ ] T051 [US6] Wire `PropagationView` into `AddEditConfigView` save action: after saving an edit, check for enabled agents (T049) → if any, present `PropagationView` as sheet before dismissing in `mcp-inator/UI/AddEditConfigView.swift`

**Checkpoint**: Editing a config and saving immediately presents the propagation offer with
diffs. Accepting updates affected agent files. Declining is safe with no state tracked.

---

## Phase 8: User Story 7 — Import Configs from an Agent (Priority: P2)

**Goal**: At any time, users can pull in MCP entries from any agent's config file using the
same per-entry diff flow as first-run discovery.

**Independent Test**: Manually add an entry to `~/.claude.json` outside mcp-inator. Open
Claude's agent view → "Import from Claude Code". ImportReviewView shows the new entry as
"new". Import it. Entry is in the library. Repeat with an entry that conflicts with an
existing library entry — diff shown.

- [ ] T052 [US7] Add "Import from [Agent]" action button to `AgentListView` (visible for any agent, triggers `ConfigStore.categorizeImport` from T035, opens `ImportReviewView`) in `mcp-inator/UI/AgentListView.swift`
- [ ] T053 [US7] Confirm `ImportReviewView` handles the manually-triggered case (same component as T034, already built; verify agent assignment is created as `enabled` for entries the user imports as "use agent version") in `mcp-inator/UI/ImportReviewView.swift`
- [ ] T054 [US7] Implement `ConfigStore.applyImportDecisions(_:agentId:)`: for each approved import entry, insert or update `MCPServerConfig` in library, create `ConfigAgentAssignment` with `state = enabled` and `lastWrittenSnapshot` set to the imported values in `mcp-inator/Store/ConfigStore.swift`

**Checkpoint**: "Import from agent" action appears for any agent. All three import categories
display correctly. Approved imports appear in library and are marked enabled for that agent.

---

## Phase 9: User Story 4 — View Config Status Across Agents (Priority: P3)

**Goal**: Users can see at a glance which configs are active for which agents, with unavailable
agents visually distinguished from simply-disabled ones.

**Independent Test**: Enable "GitHub MCP" for Claude and Gemini, disable for Codex, disconnect
Gemini's config file. Open status view: GitHub MCP shows enabled/enabled/unavailable/disabled
for the 4 agents. "Unavailable" has a distinct visual treatment with a diagnostic hint.

- [ ] T055 [US4] Implement `ConfigStore.fetchStatusMatrix()`: returns `[(MCPServerConfig, [(AgentRecord, EffectiveState)])]` where `EffectiveState` is `enabled`, `disabled`, or `unavailable` (computed from assignment state + `AgentRecord.isAvailable`) in `mcp-inator/Store/ConfigStore.swift`
- [ ] T056 [US4] Update `ConfigLibraryView` to show per-agent status badges inline for each config (enabled/disabled/unavailable with distinct colors, FR-009; "unavailable" includes short diagnostic hint) in `mcp-inator/UI/ConfigLibraryView.swift`

**Checkpoint**: Status matrix renders correctly. Unavailable is visually distinct from
disabled with a diagnostic hint explaining the cause.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Recovery paths, schema upgrade validation, error polish, Sparkle setup.

- [ ] T057 Implement store corruption recovery (FR-028): on `ConfigStore` init failure (missing or unreadable DB), start with new empty database, show one-time alert "Your previous config library was not found", immediately offer to re-import from detected agent files in `mcp-inator/App/mcp_inatorApp.swift` + `mcp-inator/Store/ConfigStore.swift`
- [ ] T058 [P] Implement delete-cascade for unavailable agents (FR-004): when deleting a config enabled for one or more unavailable agents, warn user and proceed with partial delete; show summary of which agents were updated and which were not in `mcp-inator/Store/ConfigStore.swift` + `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T059 [P] Validate schema migration path: add a no-op Migration 002 to `DatabaseMigrator`, verify existing test DB upgrades cleanly, remove no-op before ship in `mcp-inator/Store/Migrations/`
- [ ] T060 [P] Audit all `AdapterError.writeFailure` surfaces (FR-012): verify every error shown to the user includes the file path, the specific cause, and an actionable suggestion; eliminate any generic "operation failed" messages across `mcp-inator/UI/`
- [ ] T061 Configure Sparkle 2.x: add `SUFeedURL` key to `Info.plist`, create `sparkle-appcast.xml` placeholder, add Sparkle updater to `mcp_inatorApp` lifecycle in `mcp-inator/App/mcp_inatorApp.swift` + `mcp-inator/Resources/`

**Checkpoint**: App recovers gracefully from a missing store. All error messages are specific
and actionable. Sparkle updater is wired (URL is a placeholder until first release).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **blocks all user stories**
- **Phase 3 (US1)**: Depends on Phase 2 (models + store)
- **Phase 4 (US5)**: Depends on Phase 2 (all adapters: isInstalled + readConfigs)
- **Phase 5 (US2)**: Depends on Phase 2 (all adapters: writeConfigs + removeConfig) + Phase 3 (library exists to enable)
- **Phase 6 (US3)**: Depends on Phase 5 (enable flow reused)
- **Phase 7 (US6)**: Depends on Phase 3 (edit form) + Phase 5 (write flow)
- **Phase 8 (US7)**: Depends on Phase 4 (ImportReviewView built in T034) + Phase 5 (assignments)
- **Phase 9 (US4)**: Depends on Phase 3 + Phase 5 (assignments exist to query)
- **Phase 10 (Polish)**: Depends on all phases complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US5 (P1)**: Can start after Phase 2 — no dependencies on US1 (parallel with US1)
- **US2 (P1)**: Depends on US1 (needs library configs to enable)
- **US3 (P2)**: Depends on US2 (reuses enable flow)
- **US6 (P2)**: Depends on US1 (edit form) + US2 (write flow)
- **US7 (P2)**: Depends on US5 (ImportReviewView) + US5/US2 (assignments)
- **US4 (P3)**: Depends on US1 + US2 (assignments to query)

### Key Intra-Phase Dependencies

- T008 depends on T006 + T007 (all models needed before assignment model)
- T009 depends on T006–T008 (schema mirrors the models)
- T010–T012 depend on T009 (migrations run first)
- T016–T019 depend on T014 + T015 (protocol + fixtures required)
- T019 (Codex) is the most complex adapter — do last among T016–T019
- T036–T037 (enable/disable) depend on T016–T019 (all adapters must exist)
- T050 (PropagationView) depends on T036 (enable flow) for its confirm path
- T034 (ImportReviewView) is built in Phase 4 (US5) and reused in Phase 8 (US7) — do not duplicate

---

## Parallel Opportunities

### Phase 2 Parallel Block

```
After T014 (protocol) + T015 (fixtures) complete:

  T016 (ClaudeCodeAdapter)     ─┐
  T017 (ClaudeDesktopAdapter)  ─┤ all in parallel
  T018 (GeminiCLIAdapter)      ─┘
  T019 (CodexCLIAdapter)         → after T016–T018 pass (most complex, do last or in parallel)

After T006 + T007 complete:
  T008 (ConfigAgentAssignment) → T009 (Migration) → T010–T012 (ConfigStore)
  T013 (ConfigStore tests)     → in parallel with T010–T012
```

### Phase 3 Parallel Block (US1)

```
After T010–T012 (ConfigStore) complete:
  T022 + T023 (server key transform + tests)    ─┐ all in parallel
  T024 + T025 (sensitivity heuristic + tests)   ─┤
  T026 (AddEditConfigView)                       ─┤
  T027 (ConfigLibraryView shell)                 ─┘
  T028 (wire together) → after T026 + T027
```

### Phase 4 + US1 in Parallel

US5 (Phase 4) and US1 (Phase 3) can run simultaneously after Phase 2 completes — they touch
different files and have no shared in-flight dependencies.

---

## Implementation Strategy

### MVP: User Stories 1 + 2 + 5 (All P1)

1. Complete Phase 1 + Phase 2 (foundation + all adapters)
2. Complete Phase 3 (US1: config library)
3. Complete Phase 4 (US5: first-run discovery — users can import what they have)
4. Complete Phase 5 (US2: enable/disable — core value delivery)
5. **STOP and VALIDATE**: Add a config, enable it for Claude, verify the file, disable it.
   Run all adapter integration tests. This is a shippable MVP.

### Incremental Delivery (P2 Stories)

6. Phase 6 (US3: bulk apply) — adds one-step cross-agent setup
7. Phase 7 (US6: propagate edits) — eliminates manual re-sync after edits
8. Phase 8 (US7: manual import) — allows importing at any time, not just first-run

### P3 and Polish

9. Phase 9 (US4: status view) — visibility and audit
10. Phase 10 (Polish) — recovery, error polish, Sparkle

---

## Task Summary

| Phase | Story | Tasks | Parallelizable |
|-------|-------|-------|----------------|
| 1 — Setup | — | T001–T005 (5) | T003, T004, T005 |
| 2 — Foundation | — | T006–T021 (16) | T007, T013, T015, T016, T017, T018 |
| 3 — US1 | P1 | T022–T029 (8) | T023, T024, T025, T027 |
| 4 — US5 | P1 | T030–T035 (6) | — (sequential discovery flow) |
| 5 — US2 | P1 | T036–T045 (10) | — |
| 6 — US3 | P2 | T046–T048 (3) | — |
| 7 — US6 | P2 | T049–T051 (3) | — |
| 8 — US7 | P2 | T052–T054 (3) | — |
| 9 — US4 | P3 | T055–T056 (2) | — |
| 10 — Polish | — | T057–T061 (5) | T058, T059, T060 |
| **Total** | | **61 tasks** | |

---

## Notes

- `[P]` tasks operate on different files with no shared in-flight state — safe to parallelize
- `[Story]` label maps each task to its user story for traceability
- `ImportReviewView` (T034) is built in Phase 4 (US5) and **reused** in Phase 8 (US7) — one component
- `lastWrittenSnapshot` must be updated atomically with the write result in T036/T037 — critical for correct pre-flight behavior
- Codex adapter (T019) is the most complex due to TOML — allocate extra time
- All adapter tests use fixture files only — never read/write real `~/.claude.json` or `~/.codex/config.toml`
- Commit after each task or logical group; each checkpoint is a safe stopping point
