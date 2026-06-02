# Tasks: Zed Editor MCP Adapter

**Input**: Design documents from `specs/015-zed-adapter/`

**Feature**: Add `ZedAdapter` conforming to `AgentAdapter` so users can install and manage MCP servers in Zed from mcp-inator.

**Key architectural decision**: `ZedAdapter` is a custom struct (not `FileBasedAdapter`) because Zed uses a nested `{ "command": { "path": ..., "args": [...] } }` format that differs from all existing adapters. It reuses `JSONAdapterHelper.readFullJSON`, `checkDrift`, and `writeAtomic` but implements its own entry parsing and serialization.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

> **No project setup required.** Project structure, build tooling, and test infrastructure are already in place. Proceed directly to Phase 2.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the `AgentType.zed` constant and create the new source and test files as skeletons. These block all user story implementation.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T001 Add `static let zed = AgentType(rawValue: "zed")` constant to `mcp-inator/Models/AgentRecord.swift` alongside the existing agent type constants
- [ ] T002 [P] Create `ZedAdapter.swift` in `mcp-inator/Adapters/` with: injectable `homeDirectory: URL` (defaulting to `NSHomeDirectory()`), `agentType = .zed`, `displayName = "Zed"`, and stub implementations for all `AgentAdapter` protocol requirements (stubs may return `.success`, empty dict, `false`, or `.valid` as appropriate)
- [ ] T003 [P] Create `mcp-inatorTests/Integration/Fixtures/zed_settings.json` with two Zed-format `context_servers` entries (`github-mcp` with env var, `filesystem` without) plus one extra top-level key (`"otherZedSetting": true`) to verify key preservation
- [ ] T004 [P] Create `mcp-inatorTests/Integration/ZedAdapterTests.swift` with class skeleton, `setUp`/`tearDown` using a temp directory (matching the `ClaudeCodeAdapterTests` pattern), and `configURL` pointing to a temp `settings.json` path

**Checkpoint**: Project builds with the new files. Tests run (all new tests pass trivially with stubs).

---

## Phase 3: User Story 1 — Install MCP Server to Zed (Priority: P1) 🎯 MVP

**Goal**: Zed appears in the agents list when installed, and MCP servers can be written to and removed from its `context_servers` key.

**Independent Test**: Create `~/.config/zed/settings.json` with `{}`. Launch mcp-inator — Zed appears. Add a server, enable for Zed — verify `context_servers` entry written with nested `command.path`/`command.args`. Disable — verify entry removed, file otherwise unchanged.

- [ ] T005 [US1] Implement `defaultConfigPath()` returning `homeDirectory/.config/zed/settings.json` and `isInstalled()` checking file existence (`~/.config/zed/settings.json`) or parent directory existence (`~/.config/zed/`) in `mcp-inator/Adapters/ZedAdapter.swift`
- [ ] T006 [US1] Implement `readConfigs(from:)` in `mcp-inator/Adapters/ZedAdapter.swift`: read `context_servers` key via `JSONAdapterHelper.readFullJSON`, parse each entry from Zed format (`command.path` → `command`, `command.args` → `args`, top-level `env` → `envVars`)
- [ ] T007 [US1] Implement `writeConfigs(_:to:expectedExisting:)` in `mcp-inator/Adapters/ZedAdapter.swift`: read full JSON, run `JSONAdapterHelper.checkDrift` on managed keys only, serialize configs to Zed entry format, write atomically via `JSONAdapterHelper.writeAtomic`; create `context_servers` key if absent
- [ ] T008 [US1] Implement `removeConfig(key:from:expectedValue:)` in `mcp-inator/Adapters/ZedAdapter.swift`: same drift check + atomic write pattern as `writeConfigs`; remove the named key from `context_servers`
- [ ] T009 [US1] Implement `validateServerKey(_:)` in `mcp-inator/Adapters/ZedAdapter.swift` using pattern `^[a-z0-9][a-z0-9-]*$` with error message consistent with other adapters; no reserved words
- [ ] T010 [US1] Add `zedDef` (`AgentDefinition` with `agentType: .zed`, `displayName: "Zed"`, `configPathRelative: ".config/zed/settings.json"`, Zed icon colors/fallback letter "Z", standard key validation config) and append `ZedAdapter()` to `AdapterRegistry.all` in `mcp-inator/Adapters/AdapterRegistry.swift`
- [ ] T011 [US1] Add read/write/remove/preserves-keys tests to `mcp-inatorTests/Integration/ZedAdapterTests.swift`: `testRead_emptyFile`, `testRead_validFixture` (reads 2 servers from fixture, verifies `github-mcp` command/args/env), `testRead_malformedJSON` (writes `{invalid}` to configURL, asserts `readConfigs` throws), `testWrite_createsFileIfMissing`, `testWrite_mergesIntoExistingFile`, `testRemoveConfig`, `testRead_preservesUnknownKeys` (writes to fixture copy, verifies `otherZedSetting` survives)

**Checkpoint**: `make test` passes. Zed appears in the agents list when `~/.config/zed/settings.json` exists. Servers round-trip correctly through the Zed config format.

---

## Phase 4: User Story 2 — Drift Detection (Priority: P2)

**Goal**: Externally modified Zed config entries trigger a drift warning instead of being silently overwritten.

**Independent Test**: Write a server via mcp-inator. Directly edit that entry in settings.json. Attempt update/remove in mcp-inator — drift warning appears. Verify an unmanaged external entry does not trigger drift.

- [ ] T012 [US2] Add drift detection tests to `mcp-inatorTests/Integration/ZedAdapterTests.swift`: `testWrite_driftDetected` (externally changes managed entry → expects `.driftDetected`), `testWrite_driftDetected_managedKeyOnly` (externally adds unmanaged entry → expects `.success`), `testRemoveConfig_driftDetected` (externally changes entry before remove → expects `.driftDetected`)

**Checkpoint**: All drift tests pass. Drift detection verifies only managed keys, ignores unmanaged external additions.

---

## Phase 5: User Story 3 — Auto-Detection When Not Installed (Priority: P3)

**Goal**: Zed is absent from the agents list when not installed. App bundle presence alone is sufficient for detection.

**Independent Test**: Remove `~/.config/zed/` and `/Applications/Zed.app`. Restart mcp-inator — Zed absent. Create `~/.config/zed/` empty dir — Zed appears. Remove dir, create `/Applications/Zed.app` mock — Zed appears.

- [ ] T013 [US3] Add `/Applications/Zed.app` bundle presence check to `isInstalled()` in `mcp-inator/Adapters/ZedAdapter.swift` (third detection path: file exists → dir exists → app bundle exists)
- [ ] T014 [US3] Add `isInstalled()` tests to `mcp-inatorTests/Integration/ZedAdapterTests.swift`: `testIsInstalled_emptyTempDir_returnsFalse`, `testIsInstalled_settingsFileExists_returnsTrue`, `testIsInstalled_zedDirExists_returnsTrue`, `testIsInstalled_unrelatedFilesOnly_returnsFalse`, `testDefaultConfigPath_usesInjectedHomeDirectory` — all using `ZedAdapter(homeDirectory: tempDir)`

**Checkpoint**: All isInstalled tests pass. Zed correctly appears/disappears based on installation state without requiring app restart configuration.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Lint, coverage, version bump, and release notes.

- [ ] T015 Run `make lint` and fix all SwiftLint warnings in `mcp-inator/Adapters/ZedAdapter.swift` and `mcp-inatorTests/Integration/ZedAdapterTests.swift`
- [ ] T016 [P] Bump patch version in `VERSION` file (e.g. `0.4.10` → `0.4.11`)
- [ ] T017 [P] Update `RELEASE_NOTES.md` with Zed adapter addition
- [ ] T018 Run `make cover` and verify all tests pass and coverage threshold is met

**Checkpoint**: PR ready — lint clean, tests green, coverage above threshold, version bumped.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately
- **US1 (Phase 3)**: Requires Phase 2 complete (needs AgentType.zed + ZedAdapter skeleton + fixture + test file)
- **US2 (Phase 4)**: Requires Phase 3 complete (drift tests depend on writeConfigs/removeConfig implementation)
- **US3 (Phase 5)**: Requires Phase 2 complete (uses injectable homeDirectory from skeleton); can run in parallel with US2
- **Polish (Phase 6)**: Requires all implementation phases complete

### Within Each Phase

- T002, T003, T004 in Phase 2 can run in parallel (different files)
- T005–T010 in Phase 3 are sequential (each builds on the prior)
- T011 (Phase 3 tests) can run after T005–T009 are complete
- T016 and T017 in Phase 6 can run in parallel with each other

### Parallel Opportunities

```bash
# Phase 2 — launch in parallel:
Task T002: Create ZedAdapter.swift skeleton
Task T003: Create zed_settings.json fixture
Task T004: Create ZedAdapterTests.swift skeleton

# Phase 6 — launch in parallel:
Task T016: Bump VERSION
Task T017: Update RELEASE_NOTES.md
```

---

## Implementation Strategy

### MVP (US1 Only — Phase 2 + Phase 3)

1. Complete Phase 2: Foundational (T001–T004)
2. Complete Phase 3: US1 implementation (T005–T011)
3. **STOP and VALIDATE**: `make test` passes, Zed appears in UI, servers round-trip
4. Merge if sufficient — US2/US3 can follow in a subsequent PR

### Full Delivery

1. Phase 2 → Phase 3 → Phase 4 (US2) and Phase 5 (US3) in parallel → Phase 6 Polish

---

## Task Summary

| Phase | Tasks | Count |
|-------|-------|-------|
| Phase 2: Foundational | T001–T004 | 4 |
| Phase 3: US1 (Install) | T005–T011 | 7 |
| Phase 4: US2 (Drift) | T012 | 1 |
| Phase 5: US3 (Detection) | T013–T014 | 2 |
| Phase 6: Polish | T015–T018 | 4 |
| **Total** | | **18** |

**Parallel opportunities**: 6 tasks marked [P]
**MVP scope**: Phases 2–3 (11 tasks)
