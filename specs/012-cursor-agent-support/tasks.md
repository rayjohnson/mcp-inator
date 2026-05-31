# Tasks: Cursor Agent Support

**Input**: Design documents from `/specs/012-cursor-agent-support/`

**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓

**Tests**: Included — SC-004 requires `CursorAdapterTests` covering read, write, remove, isInstalled.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create test fixture so integration tests have known input data.

- [X] T001 Create test fixture `mcp-inatorTests/Fixtures/cursor_mcp.json` with two server entries (`github-mcp` stdio, `filesystem` stdio) matching the schema in `data-model.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: `AgentType.cursor` is needed by every downstream task — all user stories are blocked until this is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Add `.cursor = "cursor"` case to `AgentType` enum in `mcp-inator/Models/AgentRecord.swift`; add `.cursor` branches to `displayName` (→ `"Cursor"`), `isAppManaged` (→ `false` / default), and `defaultConfigPath` (→ `"\(home)/.cursor/mcp.json"`)

**Checkpoint**: `AgentType.cursor` compiles. All existing tests still pass (`make cover`).

---

## Phase 3: User Story 1 — Cursor appears in Agents after discovery (Priority: P1) 🎯 MVP

**Goal**: When mcp-inator discovers agents, Cursor appears in the Agents panel with correct icon, name, and config path, whenever `~/.cursor/` or `~/.cursor/mcp.json` exists.

**Independent Test**: Create `~/.cursor/` directory. Open mcp-inator. Verify Cursor appears in the Agents list with the "C" badge icon (or real Cursor app icon if installed) and the path `~/.cursor/mcp.json`. Remove `~/.cursor/` — verify Cursor disappears.

### Implementation for User Story 1

- [X] T003 [US1] Create `mcp-inator/Adapters/CursorAdapter.swift` implementing `AgentAdapter` in full: `agentType = .cursor`, `displayName = "Cursor"`, `defaultConfigPath()` → `~/.cursor/mcp.json`, `isInstalled()` checks file OR parent dir, `readConfigs(from:)` via `JSONAdapterHelper` with `mcpKey: "mcpServers"`, `writeConfigs(_:to:expectedExisting:)` via `JSONAdapterHelper`, `removeConfig(key:from:expectedValue:)` via `JSONAdapterHelper`, `validateServerKey(_:)` → `^[a-z0-9][a-z0-9-]*$`
- [X] T004 [P] [US1] Add `CursorAdapter()` to the `adapters` array in `mcp-inator/App/mcp_inatorApp.swift` (after `GeminiDesktopAdapter()`)
- [X] T005 [P] [US1] Add `CursorAdapter()` to `allAdapters` computed property in `mcp-inator/UI/MenuBarView.swift`
- [X] T006 [US1] Add `.cursor` case to `AgentIcon.swift`: new private `CursorAppIcon` struct that attempts `NSWorkspace` lookup for bundle ID `"com.todesktop.230313mzl4w4u92"` then `/Applications/Cursor.app` path, falling back to `LetterBadge(letter: "C", background: Color(red: 0.07, green: 0.07, blue: 0.07))`; add `case .cursor: CursorAppIcon()` to `AgentIcon.body`

### Tests for User Story 1

- [X] T007 [P] [US1] Create `mcp-inatorTests/Integration/CursorAdapterTests.swift` with test cases: `testIsInstalled_fileExists`, `testIsInstalled_dirExistsNoFile`, `testIsInstalled_neitherExists`, `testRead_emptyFile`, `testRead_validFixture` (loads `cursor_mcp.json` fixture, asserts count == 2 and `configs["github-mcp"] != nil`), `testValidateServerKey_valid`, `testValidateServerKey_invalid` — mirrors `ClaudeDesktopAdapterTests` setup/teardown pattern

**Checkpoint**: `make cover` passes. Cursor appears in Agents panel when `~/.cursor/` exists.

---

## Phase 4: User Story 2 — Enable / disable library servers for Cursor (Priority: P1)

**Goal**: Toggling a server on for Cursor writes it to `~/.cursor/mcp.json`; toggling off removes it. Drift detection fires if the file was modified externally.

**Independent Test**: Enable a library server for Cursor via the Agents panel. Open `~/.cursor/mcp.json` in a text editor — the entry should be present. Disable it — the entry should be removed. Manually edit the file, then try to toggle — the UI should show a drift/conflict error.

### Tests for User Story 2

- [X] T008 [P] [US2] Extend `mcp-inatorTests/Integration/CursorAdapterTests.swift` with: `testWrite_createsFileIfMissing`, `testWrite_mergesIntoExistingFile`, `testWrite_removesDisabledConfig`, `testWrite_driftDetected`, `testWrite_driftDetected_managedKeyOnly`, `testWrite_atomicOnCrash`, `testWrite_removeConfig_driftDetected` — all mirrors of `ClaudeDesktopAdapterTests` equivalents

**Checkpoint**: All write/remove/drift tests pass. No new implementation code needed beyond T003.

---

## Phase 5: User Story 3 — Import existing Cursor MCP servers into the library (Priority: P2)

**Goal**: Servers already in `~/.cursor/mcp.json` can be imported into the mcp-inator library via the existing Import flow (ImportReviewView). No new code is required — the import flow already calls `adapter.readConfigs(from:)` on any registered adapter.

**Independent Test**: Pre-populate `~/.cursor/mcp.json` with 2 servers. Open mcp-inator → Agents → Cursor → Import. Both servers should appear as importable/new entries in `ImportReviewView`. Confirm import — both appear in the library.

### Tests for User Story 3

- [X] T009 [US3] Extend `mcp-inatorTests/Integration/CursorAdapterTests.swift` with: `testRead_preservesUnknownKeys` (verifies round-trip: write a config with an unknown top-level key, read back, write again — unknown keys survive); `testRead_emptyMcpServersKey` (fixture with `{"mcpServers": {}}` → returns empty dict, no crash)

**Checkpoint**: Import flow surfaces Cursor configs in `ImportReviewView`. All adapter tests pass.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T010 [P] `touch` all modified Swift files then run `make lint` and fix all SwiftLint warnings (pay attention to `force_unwrapping`, `identifier_name`, `multiple_closures_with_trailing_closure`)
- [X] T011 [P] Run `make cover` and verify all existing tests still pass and coverage threshold is met

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (fixture can be created in parallel but enum must compile first for adapter)
- **US1 (Phase 3)**: Depends on Phase 2 complete — T003, T004, T005, T006 can all start after T002; T004/T005 can run in parallel with T006
- **US2 (Phase 4)**: Depends on T003 (adapter already written); T008 adds tests only
- **US3 (Phase 5)**: Depends on T003 (readConfigs already implemented); T009 adds tests only
- **Polish (Phase 6)**: Depends on all story phases complete

### User Story Dependencies

- **US1 (P1)**: Unblocked after Foundation — pure discovery, no dependency on US2/US3
- **US2 (P1)**: Unblocked after US1 adapter (T003) — write/remove already implemented in CursorAdapter
- **US3 (P2)**: Unblocked after US1 adapter (T003) — readConfigs already implemented in CursorAdapter

### Within Each User Story

- T003 before T004/T005/T006 (adapter needed for registration to compile)
- T003 before T007 (tests need the implementation to import)
- T007 before T008 (same file; extend rather than replace)
- T008 before T009 (same file)

### Parallel Opportunities

- T001 runs immediately, in parallel with T002
- T004, T005, T006, T007 all run in parallel after T003 compiles
- T008, T009 can run sequentially in the same file after T007
- T010, T011 run in parallel in Polish phase

---

## Parallel Example: User Story 1 (after T003 is done)

```text
T004: Add CursorAdapter() to mcp_inatorApp.swift
T005: Add CursorAdapter() to MenuBarView.swift
T006: Add .cursor case to AgentIcon.swift
T007: Write CursorAdapterTests.swift — isInstalled + read tests
```

---

## Implementation Strategy

### MVP (User Stories 1 + 2 only — P1 stories)

1. Complete Phase 1 (T001): Create fixture
2. Complete Phase 2 (T002): Add AgentType.cursor
3. Complete Phase 3 (T003–T007): Adapter + registration + icon + isInstalled/read tests
4. Complete Phase 4 (T008): Write/remove/drift tests
5. **STOP and VALIDATE**: `make cover` passes; manual test in running app
6. Skip US3 (P2) if time-constrained

### Full Delivery (all 3 stories)

1. MVP above
2. Phase 5 (T009): Add read edge-case tests
3. Manual import flow smoke test
4. Phase 6 (T010–T011): Lint + coverage

---

## Notes

- No database migration required — `AgentType` raw string storage is backward-compatible
- `CursorAdapter` is ~50 lines; mirrors `ClaudeDesktopAdapter` almost exactly
- All `JSONAdapterHelper` behaviour (drift detection, atomic write, unknown-key preservation) is inherited for free
- `AgentIcon.CursorAppIcon` follows the same `NSWorkspace` pattern as `GeminiDesktopAppIcon`
- After implementation, bump `VERSION` and update `RELEASE_NOTES.md` before PR (`CLAUDE.md` requirement)
