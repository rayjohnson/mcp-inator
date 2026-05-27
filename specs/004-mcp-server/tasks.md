---
description: "Task list for Built-in MCP Server feature"
---

# Tasks: Built-in MCP Server

**Input**: Design documents from `/specs/004-mcp-server/`

**Branch**: `004-mcp-server`

**Organization**: Tasks are grouped by user story. Each story is independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other [P] tasks in the same phase
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: Add SDK dependency and replace `@main` entry point.

- [X] T001 Add `modelcontextprotocol/swift-sdk` (from: "0.9.0") package to `project.yml` under `packages:` and as a dependency of the `mcp-inator` target, then run `xcodegen generate` to regenerate `mcp-inator.xcodeproj`
- [X] T002 Remove `@main` attribute from `mcp-inator/App/mcp_inatorApp.swift`; create `mcp-inator/App/main.swift` with a two-branch entry: if `CommandLine.arguments.contains("--mcp-server")` call `MCPServerRunner.runSynchronously()`, else call `mcp_inatorApp.main()`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Data model additions and self-entry seeding that all user stories depend on.

**⚠️ CRITICAL**: Must complete before Phase 3+.

- [X] T003 Add `var isBuiltIn: Bool { serverKey == "mcp-inator" }` computed property to `MCPServerConfig` in `mcp-inator/Models/MCPServerConfig.swift`
- [X] T004 Add `func seedSelfEntry() throws` to `ConfigStore` in `mcp-inator/Store/ConfigStore.swift` — upsert an `MCPServerConfig` with `displayName: "mcp-inator"`, `serverKey: "mcp-inator"`, `command: ""`, `args: ["--mcp-server"]`; use `INSERT OR IGNORE` semantics (skip if already present); call this from `mcp_inatorApp`'s `onAppear` block in `mcp-inator/App/mcp_inatorApp.swift`

**Checkpoint**: `isBuiltIn` resolves correctly; `seedSelfEntry()` inserts the row once and is idempotent.

---

## Phase 3: User Story 1 — AI agents manage servers via stdio (P1) 🎯 MVP

**Goal**: A MCP-compatible client can call all six tools against a running `mcp-inator --mcp-server` process.

**Independent Test**: Run `echo '<initialize>\n<tools/list>\n<tools/call list_servers>' | ./mcp-inator --mcp-server` (using the quickstart.md payloads) and confirm well-formed JSON responses for each message.

### Implementation

- [X] T005 [US1] Create `mcp-inator/MCP/MCPTools.swift` — implement six functions, each taking a `ConfigStore` and the tool's arguments, returning `(content: [Tool.Content], isError: Bool)`:
  - `listServers(store:)` → JSON array of `{serverKey, displayName, command, args, transportType}`
  - `addServer(store:name:command:args:env:)` → insert via `store.insert`; error if duplicate serverKey
  - `removeServer(store:serverName:)` → fetch by serverKey, call `store.delete`; error if not found or `isBuiltIn`
  - `enableServer(store:serverName:agent:)` → resolve agent from `store.agents`, check `!agentType.isAppManaged`, call `store.enableConfig`; error if agent/server not found or app-managed
  - `disableServer(store:serverName:agent:)` → same lookup, call `store.disableConfig`; same error conditions
  - `listAgents(store:)` → JSON array of `{agentType, displayName, configPath, isAvailable}` from `store.agents`
  - For `enableServer` on the `"mcp-inator"` entry: resolve command from `Bundle.main.executableURL.path` before calling adapter (see T011)
- [X] T006 [US1] Create `mcp-inator/MCP/MCPServer.swift` — define `MCPServerRunner` with:
  - `static func runSynchronously()` — creates a `DispatchSemaphore`, starts a `Task { try? await runAsync(); sema.signal() }`, then calls `sema.wait()`
  - `static func runAsync() async throws` — initializes `ConfigStore()`, calls `store.seedSelfEntry()`, creates `MCP.Server(name: "mcp-inator", version: "0.1.0", capabilities: .init(tools: .init()))`, registers `ListTools` handler returning all six tool definitions with `inputSchema` per `contracts/mcp-tools.md`, registers `CallTool` handler dispatching to `MCPTools`, starts `StdioTransport`
- [X] T007 [US1] Verify `mcp-inator/App/main.swift` correctly calls `MCPServerRunner.runSynchronously()` in the `--mcp-server` branch (from T002); confirm `mcp_inatorApp.main()` path is unchanged
- [X] T008 [US1] Create `mcp-inatorTests/Integration/MCPServerTests.swift` — end-to-end tests using `Process` + `Pipe` to drive `mcp-inator --mcp-server` via stdin/stdout:
  - `testInitializeHandshake` — sends initialize, expects result with protocolVersion and tools capability
  - `testToolsList` — sends tools/list, expects all six tool names
  - `testAddAndListServer` — calls add_server then list_servers, confirms new entry present
  - `testRemoveServer` — adds then removes, confirms gone from list_servers
  - `testEnableDisableServer` — enable for claude_code, confirm config file written; disable, confirm removed
  - `testCannotRemoveBuiltIn` — calls remove_server("mcp-inator"), expects isError: true
  - `testAppManagedAgentError` — calls enable_server with agent: "gemini_desktop", expects isError: true
  - `testListAgents` — calls list_agents, expects JSON array (may be empty if no agents discovered)

**Checkpoint**: `mcp-inator --mcp-server` responds correctly to all six tools. Integration tests pass.

---

## Phase 4: User Story 2 — Pinned non-editable self-entry in UI (P2)

**Goal**: The Servers tab shows the mcp-inator entry with a lock badge and no edit/delete controls.

**Independent Test**: Launch the app; open the Servers tab; confirm "mcp-inator" row has a lock badge and swipe-to-delete / edit button are absent.

### Implementation

- [X] T009 [P] [US2] In `mcp-inator/UI/ConfigLibraryView.swift` — add a lock badge (SF Symbol `lock.fill`) to the row subtitle or trailing area for entries where `config.isBuiltIn`; use `.foregroundColor(.secondary)` to keep it subtle
- [X] T010 [P] [US2] In `mcp-inator/UI/ConfigLibraryView.swift` — conditionally suppress the swipe-delete action and the edit navigation for `isBuiltIn` entries (wrap the `.onDelete` handler and the edit `NavigationLink` with `if !config.isBuiltIn`)

**Checkpoint**: mcp-inator entry visible with lock badge; edit and delete are inaccessible.

---

## Phase 5: User Story 3 — Bundle-relative binary path (P3)

**Goal**: `enable_server` for the mcp-inator entry writes the current bundle's executable path, not a stored literal.

**Independent Test**: Move the .app to a new location; call `enable_server` for mcp-inator via the MCP server; confirm the written command in `claude_desktop_config.json` matches the new path.

### Implementation

- [X] T011 [US3] In `mcp-inator/MCP/MCPTools.swift` `enableServer` function — before calling `store.enableConfig`, if `serverName == "mcp-inator"`, fetch the config, set `config.command = Bundle.main.executableURL?.path ?? ""`, then pass the modified config to the adapter rather than the stored one (or update it in the DB first via `store.update`)

**Checkpoint**: Written claude_desktop_config.json contains the live bundle path for the mcp-inator entry.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T012 Verify build clean with zero warnings: `xcodebuild build -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug`
- [X] T013 Verify all tests pass: `xcodebuild test -project mcp-inator.xcodeproj -scheme mcp-inator -destination 'platform=macOS'`
- [X] T014 Run through quickstart.md Scenario 1–5 manually using the built binary; confirm each produces the expected output

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start here
- **Foundational (Phase 2)**: Depends on Phase 1 — blocks all user story work
- **US1 (Phase 3)**: Depends on Phase 2 — core value delivery
- **US2 (Phase 4)**: Depends on Phase 2 (needs `isBuiltIn`); independent of Phase 3
- **US3 (Phase 5)**: Depends on Phase 3 T005 (`enableServer` function exists)
- **Polish (Phase 6)**: Depends on all desired phases complete

### User Story Dependencies

- **US1**: No story dependencies — standalone after Foundational
- **US2**: No story dependencies — standalone after Foundational; T009 and T010 can run in parallel
- **US3**: Depends on US1 T005 (`enableServer` in MCPTools.swift must exist first)

---

## Parallel Opportunities

Within Phase 3 (US1): T005 and T007 both touch different files and can start in parallel; T006 depends on T005 being complete enough to compile.

Within Phase 4 (US2): T009 and T010 both edit `ConfigLibraryView.swift` — run sequentially to avoid conflicts.

US2 (Phase 4) and US3 (Phase 5) can run in parallel with each other after Phase 3 is complete.

---

## Implementation Strategy

### MVP (US1 only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T004)
3. Complete Phase 3: US1 (T005–T008)
4. **STOP and validate**: run integration tests, manually test with `echo | mcp-inator --mcp-server`
5. Ship — agents can now control mcp-inator

### Full Delivery

After MVP: add US2 (lock badge in UI) → add US3 (live bundle path) → Polish.

---

## Notes

- The MCP Swift SDK (`modelcontextprotocol/swift-sdk`) handles all JSON-RPC framing, the initialize handshake, and ping responses — no custom protocol code needed
- `MCPTools.swift` functions are plain Swift (not actor-isolated); `ConfigStore` is `@MainActor` so tool functions must be called from within an async context or wrapped with `MainActor.run {}`
- The `mcp-inator --mcp-server` binary must be code-signed to access the DB in `~/Library/Application Support/` — the existing app entitlements cover this
- `remove_server("mcp-inator")` returns `isError: true` (tool error, not JSON-RPC error)
- `enable_server` / `disable_server` on an app-managed agent (e.g., `gemini_desktop`) returns `isError: true` with message `"'gemini_desktop' is app-managed — MCP configuration cannot be written by mcp-inator"`
