# Tasks: Import MCP Servers from Agent Config Files

**Input**: Design documents from `specs/009-agent-config-import/`

**User Stories**:
- US1 (P1): Import from Claude Desktop
- US2 (P1): Import from Gemini CLI
- US3 (P2): Gemini Desktop shown as disabled ("managed in-app")
- US4 (P1): Import works without pre-registered agents (root fix)

**Note**: US1, US2, and US4 share identical infrastructure (same scanner, same view change, same store fix). They are implemented together in Phase 3. US3 requires no additional implementation — it is a natural output of the scanner's `isAppManaged` handling, which is covered by the scanner tests.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story this task belongs to

---

## Phase 1: Setup

**Purpose**: Register new source files in the project before any implementation begins. This prevents Xcode build failures caused by files that exist on disk but aren't in `project.pbxproj`.

- [ ] T001 Add `mcp-inator/Models/ImportSource.swift` to app target in `project.yml`
- [ ] T002 Add `mcp-inator/Services/ImportSourceScanner.swift` to app target in `project.yml`
- [ ] T003 Add `mcp-inatorTests/TestHelpers/StubAdapter.swift` to test target in `project.yml`
- [ ] T004 Add `mcp-inatorTests/Unit/ImportSourceScannerTests.swift` to test target in `project.yml`
- [ ] T005 Run `xcodegen generate` (or equivalent) to apply `project.yml` changes and confirm clean build before proceeding

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: New types and test infrastructure that all user story phases depend on. Must be complete before Phases 3–4 can begin.

**⚠️ CRITICAL**: No user story implementation can start until T006–T009 are complete.

- [ ] T006 [P] Create `mcp-inator/Models/ImportSource.swift` with `internal` struct: fields `displayName: String`, `agentType: AgentType`, `adapter: any AgentAdapter`, `configPath: URL`, `isImportable: Bool`, `unavailableReason: String?`
- [ ] T007 [P] Create `mcp-inator/Services/ImportSourceScanner.swift` with `struct ImportSourceScanner` — fields `adapters: [any AgentAdapter]` and `fileExists: (URL) -> Bool`, default initializer using all five production adapters and `FileManager.default.fileExists(atPath:)`, and `func scan() -> [ImportSource]` implementing the construction rules from `contracts/ImportSource.md`
- [ ] T008 [P] Create `mcp-inatorTests/TestHelpers/StubAdapter.swift` — `final class StubAdapter: AgentAdapter` with configurable `installedResult: Bool`, `appManagedResult: Bool`, `configPathResult: URL`, `readResult: [String: MCPServerConfig]`; defaults: installed=true, appManaged=false, configPath=/dev/null
- [ ] T009 Make `agentId` optional in `ConfigStore.applyImportDecisions` in `mcp-inator/Store/ConfigStore.swift`: change `agentId: Int64` → `agentId: Int64?`, wrap all `setAssignmentState` calls in `if let agentId { ... }`

**Checkpoint**: Build must succeed with no errors before proceeding. Run `make build` to verify.

---

## Phase 3: US1 + US2 + US4 — Import from Installed File-Backed Agents (Priority: P1) 🎯 MVP

**Goal**: Any installed, file-backed agent (Claude Desktop, Claude Code, Gemini CLI, Codex CLI) appears in the Import menu and can be imported from — even if the user has never registered that agent in mcp-inator.

**Independent Test**: Install Claude Desktop with ≥1 MCP server configured → open mcp-inator fresh (no agents registered) → click Import… → Claude Desktop appears in the menu → select it → review screen shows the server(s) → import → servers appear in the Servers tab library. Repeat with Gemini CLI config file present.

### Tests (write before implementation — they should initially fail)

- [ ] T010 [P] [US4] Write `ImportSourceScannerTests` in `mcp-inatorTests/Unit/ImportSourceScannerTests.swift` covering all 5 `StubAdapter` scenarios: (1) installed + file exists → `isImportable: true`, (2) installed + file missing → excluded, (3) not installed → excluded, (4) app-managed + installed → `isImportable: false` with reason, (5) app-managed + not installed → excluded; also cover mixed-adapter list and `unavailableReason` containing `displayName`
- [ ] T011 [P] [US1] Add `testCategorizeImport_*` cases to `mcp-inatorTests/Unit/ConfigStoreTests.swift`: new server → `.new`, exact match → `.exactMatch`, conflict → `.conflict`, built-in key "mcp-inator" → skipped, empty adapter → empty result (use `StubAdapter.readResult` to control returned configs)
- [ ] T012 [P] [US1] Add `testApplyImportDecisions_nilAgentId_*` cases to `mcp-inatorTests/Unit/ConfigStoreTests.swift`: `agentId: nil` inserts `MCPServerConfig`, `agentId: nil` creates no `ConfigAgentAssignment`, `agentId: nil` updates existing config; also add regression cases: `agentId` set inserts config AND creates assignment

### Implementation

- [ ] T013 [US4] Update `mcp-inator/UI/ConfigLibraryView.swift`: remove `private let adapters: [AgentType: any AgentAdapter]` dictionary; replace `importableAgents: [AgentRecord]` computed property with `importSources: [ImportSource] { ImportSourceScanner().scan() }`; rename `@State private var importAgent: AgentRecord?` → `@State private var importSource: ImportSource?`
- [ ] T014 [US4] Update `prepareImport` in `mcp-inator/UI/ConfigLibraryView.swift`: change signature to `prepareImport(for source: ImportSource)`, call `store.categorizeImport(from: source.adapter, configPath: source.configPath)`, set `importSource = source`; update `navigationDestination` binding to use `importSource`
- [ ] T015 [US4] Update Import menu block in `mcp-inator/UI/ConfigLibraryView.swift`: replace `ForEach(importableAgents)` with `ForEach(importSources, id: \.agentType)`; add `.disabled(!source.isImportable)` and `.help(source.unavailableReason ?? "")` to each `Button`
- [ ] T016 [US1] Update `mcp-inator/UI/ImportReviewView.swift`: change `let agent: AgentRecord` → `let source: ImportSource`; update navigation title to `"Import from \(source.displayName)"`; remove `guard let agentId = agent.id`; call `store.applyImportDecisions(toImport, agentId: nil)`; update call site in `ConfigLibraryView.navigationDestination`

**Checkpoint**: Run `make test` — all new tests must pass. Launch app, open Import menu, verify Claude Desktop and/or Gemini CLI appear without any prior agent registration.

---

## Phase 4: US3 — Gemini Desktop Disabled State (Priority: P2)

**Goal**: When Gemini Desktop is installed, it appears in the Import menu greyed out with a tooltip explaining that its MCP servers are managed internally.

**Independent Test**: With `/Applications/Gemini.app` present → open Import menu → "Gemini Desktop" appears in a visually distinct disabled state → hovering shows tooltip "MCP servers are managed inside the Gemini Desktop app" → clicking has no effect.

**Note**: This phase requires zero new implementation — `GeminiDesktopAdapter.isAppManaged` is already `true`, so the scanner already produces `isImportable: false` for it, and the menu already renders it disabled (T015). This phase is validation and test-coverage only.

- [ ] T017 [US3] Verify `GeminiDesktopAdapterTests` in `mcp-inatorTests/Unit/GeminiDesktopAdapterTests.swift` already covers `isAppManaged == true` (it does — `testIsAppManaged`); if not, add assertion
- [ ] T018 [US3] Run the app with Gemini Desktop installed and manually verify: Import menu shows "Gemini Desktop" greyed; tooltip is visible on hover; clicking does nothing; Gemini Desktop absent when app not installed

**Checkpoint**: US3 is complete when T017–T018 pass with Gemini Desktop installed.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T019 Run `make lint` (SwiftLint) and fix any warnings introduced by new files
- [ ] T020 Run `make test` for full test suite — confirm no regressions in existing adapter, ConfigStore, or visibility tests
- [ ] T021 [P] Verify empty-state behaviour: with no agents installed, Import button is hidden (not shown as empty menu)
- [ ] T022 [P] Verify error-state behaviour: corrupt/unparseable config file → review screen shows error message, not a crash
- [ ] T023 Update `specs/009-agent-config-import/contracts/ImportSource.md` if any interface details changed during implementation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — do first, always
- **Phase 2 (Foundational)**: Depends on Phase 1 — **blocks all user story phases**
- **Phase 3 (US1+US2+US4)**: Depends on Phase 2 completion
- **Phase 4 (US3)**: Depends on Phase 3 completion (needs T015 menu rendering)
- **Phase 5 (Polish)**: Depends on Phase 3 + Phase 4 completion

### Within Phase 3

- T010–T012 (tests) must be written **before** T013–T016 (implementation)
- T013 and T014 are in the same file (`ConfigLibraryView`) — do sequentially
- T015 follows T013/T014 (depends on `importSources` and `prepareImport` being updated)
- T016 (`ImportReviewView`) can be done in parallel with T013–T015 (different file)

### Parallel Opportunities

```
# Phase 2 — all parallel (different files):
T006  Create ImportSource.swift
T007  Create ImportSourceScanner.swift
T008  Create StubAdapter.swift
T009  Update ConfigStore (different file from T006-T008)

# Phase 3 tests — parallel (different files/test classes):
T010  ImportSourceScannerTests
T011  ConfigStoreTests (categorizeImport)
T012  ConfigStoreTests (applyImportDecisions)   ← same file as T011, do sequentially

# Phase 3 implementation:
T013+T014+T015  ConfigLibraryView (sequential, same file)
T016            ImportReviewView  (parallel with T013-T015)
```

---

## Implementation Strategy

### MVP (Phase 1 + 2 + 3 Only)

1. Complete Phase 1: register files in project
2. Complete Phase 2: foundational types and ConfigStore fix
3. Write tests (T010–T012) — confirm they fail
4. Complete Phase 3 implementation (T013–T016) — confirm tests pass
5. **STOP and VALIDATE**: launch app, import from Claude Desktop without prior registration

### Incremental Beyond MVP

1. MVP done → US1/US2/US4 all work
2. Add Phase 4 (T017–T018) → US3 (Gemini Desktop greyed)
3. Add Phase 5 (T019–T023) → polish and edge cases
4. Cut PR and merge

---

## Notes

- `StubAdapter` (T008) replaces the need to copy `MockAdapter` pattern per test file — it should become the canonical test double for adapter-related tests across the project
- `ImportSourceScanner` is a pure value type: no UI imports, no SwiftUI, no AppKit — keep it that way
- Never pass `FileManager.default` directly into scanner in tests — always inject the `fileExists` closure
- `agentId: nil` in `applyImportDecisions` is the intended path for this feature; passing a real `agentId` is the existing discovery flow — both must keep working
