# Tasks: MCP Server Connection Test

**Input**: Design documents from `specs/008-mcp-connection-test/`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create new source files and regenerate the Xcode project so the build is clean before implementation begins.

- [ ] T001 Create empty `mcp-inator/Models/ConnectionTestResult.swift` (placeholder — filled in Phase 2)
- [ ] T002 [P] Create empty `mcp-inator/Services/ConnectionTester.swift` (placeholder — filled in Phase 2)
- [ ] T003 Run `xcodegen generate` to incorporate new files into `mcp-inator.xcodeproj`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core types that both user stories and the UI depend on. Must be complete before any UI or service logic is written.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Implement `ConnectionTestResult` enum in `mcp-inator/Models/ConnectionTestResult.swift` — cases: `.success(elapsedSeconds: Double)`, `.launchError(detail: String)`, `.protocolError(detail: String)`, `.timeout`; add a computed `isSuccess: Bool` and `shortLabel: String` for UI convenience
- [ ] T005 Implement `ConnectionTester` actor stub in `mcp-inator/Services/ConnectionTester.swift` — declare `func test(config: MCPServerConfig) async -> ConnectionTestResult` with a placeholder `return .timeout` body so the project compiles before implementation

**Checkpoint**: Project compiles with new types present. UI can reference `ConnectionTestResult` and `ConnectionTester` before they are fully implemented.

---

## Phase 3: User Story 1 — Test a Server Before Adding It to an Agent (Priority: P1) 🎯 MVP

**Goal**: A "Test Connection" button appears in the server detail view for stdio servers. Pressing it runs the MCP initialize handshake and shows success (with elapsed time) or a generic failure indicator inline.

**Independent Test**: Open any stdio server in `AddEditConfigView`, press "Test Connection", and verify a result appears within 15 seconds without changing any config or agent assignment.

### Implementation for User Story 1

- [ ] T006 [US1] Implement process launch in `mcp-inator/Services/ConnectionTester.swift` — create `Foundation.Process` with `config.command`, `config.args`, and `config.envVars` merged into `ProcessInfo.processInfo.environment`; attach `Pipe` for stdin, stdout, and stderr; call `process.launch()`; catch `POSIXError` / `NSError` and return `.launchError(detail: error.localizedDescription)`
- [ ] T007 [US1] Implement MCP handshake in `mcp-inator/Services/ConnectionTester.swift` — after successful launch, create `StdioTransport(input: FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor), output: FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor))`; create `Client(info: .init(name: "mcp-inator-tester", version: "1"))` and call `try await client.connect(transport: transport)`; record elapsed time; call `await client.disconnect()` and `process.terminate()` in all paths
- [ ] T008 [US1] Implement 15-second timeout race in `mcp-inator/Services/ConnectionTester.swift` — wrap the `client.connect()` call in `withThrowingTaskGroup(of: ConnectionTestResult.self)` with two arms: arm A performs the handshake and returns `.success(elapsedSeconds:)`; arm B calls `try await Task.sleep(for: .seconds(15))` then returns `.timeout`; cancel the group as soon as one arm returns
- [ ] T009 [P] [US1] Add `@State private var testResult: ConnectionTestResult?`, `@State private var isTesting = false`, and `private let tester = ConnectionTester()` to `mcp-inator/UI/AddEditConfigView.swift`
- [ ] T010 [US1] Add "Test Connection" button to `mcp-inator/UI/AddEditConfigView.swift` — place it in the stdio section, visible only when `!isHTTP && !command.isEmpty`; button is disabled when `isTesting`; on tap: `Task { isTesting = true; testResult = await tester.test(config: currentConfig()); isTesting = false }` where `currentConfig()` builds an `MCPServerConfig` from current form state without saving
- [ ] T011 [US1] Add `ConnectionTestResultView` as a private sub-view at the bottom of `mcp-inator/UI/AddEditConfigView.swift` — shows a `ProgressView` when `isTesting`; when `testResult != nil` shows a colored label: green `checkmark.circle` + "Connected in X.Xs" for `.success`, red `xmark.circle` + short message for all failure cases; use `.font(.caption)` to keep it compact

**Checkpoint**: User Story 1 complete. Open a real stdio server (e.g. `npx -y @modelcontextprotocol/server-filesystem /tmp`), press "Test Connection", and see a success result. Open a server with a bad command and see a failure result.

---

## Phase 4: User Story 2 — Distinguish Between Startup Failure and Protocol Failure (Priority: P2)

**Goal**: Error messages identify the specific failure category — missing binary, non-zero exit, or timeout — not just a generic "failed."

**Independent Test**: Configure three servers: (1) non-existent binary, (2) `cat` (starts but never responds), (3) a server that exits with code 1 immediately. Each shows a meaningfully different error message.

### Implementation for User Story 2

- [ ] T012 [US2] Enrich launch error messages in `mcp-inator/Services/ConnectionTester.swift` — after `process.launch()`, also capture stderr by reading `stderrPipe.fileHandleForReading.availableData` after the process exits; include up to 200 chars of stderr in the `.launchError(detail:)` message alongside the exit code: e.g. `"Exited with code 1: <stderr>"`
- [ ] T013 [US2] Classify protocol errors distinctly in `mcp-inator/Services/ConnectionTester.swift` — when `client.connect()` throws but the process did launch successfully (i.e. we reach the transport stage before the error), return `.protocolError(detail: error.localizedDescription)` instead of `.launchError`
- [ ] T014 [US2] Update `ConnectionTestResultView` in `mcp-inator/UI/AddEditConfigView.swift` to surface distinct wording per case: `.launchError` → "Could not start: <detail>"; `.protocolError` → "Started but no MCP response: <detail>"; `.timeout` → "No response after 15 s"; all shown in red with `xmark.circle` icon

**Checkpoint**: User Stories 1 and 2 complete. Run quickstart.md scenarios 2 and 3 and verify each shows a distinct, informative message.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Include the pre-existing Sparkle quarantine fix, bump the version, and update release notes for this PR.

- [ ] T015 Stage `mcp-inator/App/mcp_inatorApp.swift` (unstaged `SparkleDelegate` quarantine-strip change) — this fix is already in the working tree from a prior session; verify with `git diff mcp-inator/App/mcp_inatorApp.swift` and commit it as part of this branch
- [ ] T016 [P] Bump `VERSION` from `0.1.4` to `0.1.5`
- [ ] T017 [P] Update `RELEASE_NOTES.md` with new user-facing changes for 0.1.5
- [ ] T018 Run quickstart.md scenarios 1–6 manually against the debug build to confirm all pass
- [ ] T019 Run `make lint` (SwiftLint) and fix any warnings in new files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (xcodegen run)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (needs `ConnectionTestResult` and `ConnectionTester` stub)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (enriches the same `ConnectionTester` and result view)
- **Polish (Phase 5)**: Depends on Phase 4

### Within Each User Story

- T006 (process launch) → T007 (MCP handshake) → T008 (timeout race): sequential, same file
- T009 (state vars) can run in parallel with T006–T008 (different file)
- T010 (button) depends on T009 (state vars)
- T011 (result view) depends on T010 (button wired up)

### Parallel Opportunities

- T001 and T002 can be created in parallel (different files)
- T009 can be done while T006–T008 are in progress (different file)
- T016 and T017 can be done in parallel (different files)

---

## Parallel Example: User Story 1

```
# These can run in parallel:
T009 — Add state vars to AddEditConfigView.swift
T006 — Implement process launch in ConnectionTester.swift

# Then sequentially:
T007 — Add MCP handshake (depends on T006)
T008 — Add timeout race (depends on T007)
T010 — Add button (depends on T009)
T011 — Add result view (depends on T010)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Press "Test Connection" on a real server; confirm success and failure both show
5. Proceed to US2 only after US1 is confirmed working

### Incremental Delivery

1. Phase 1–2: Types exist, project compiles
2. Phase 3: Basic pass/fail test button works
3. Phase 4: Rich, classified error messages
4. Phase 5: Sparkle fix + version bump + release notes → PR ready

---

## Notes

- `ConnectionTester` is an `actor` to safely manage the in-flight `Process` and avoid duplicate tests
- `currentConfig()` helper in `AddEditConfigView` builds an unsaved `MCPServerConfig` from form state — do NOT save to the store; this keeps FR-008 (no side effects) satisfied
- HTTP/SSE servers: the button is hidden entirely — no "unsupported" message needed since those users never see it
- The `SparkleDelegate` quarantine fix (T015) is already in the working tree; just stage and commit it here rather than opening a separate PR
