# Implementation Plan: MCP Server Connection Test

**Branch**: `008-mcp-connection-test` | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-mcp-connection-test/spec.md`

## Summary

Add a "Test Connection" button to the server detail view (`AddEditConfigView`) that launches the stdio server process, performs the MCP `initialize` handshake via the bundled `modelcontextprotocol/swift-sdk` Client, and displays the result (success with elapsed time, or a classified error) inline. The test is scoped to stdio servers only, is on-demand, and leaves all stored config unchanged.

## Technical Context

**Language/Version**: Swift 5.9+, SwiftUI, macOS 13+

**Primary Dependencies**: `modelcontextprotocol/swift-sdk` (MCP product — already in project), Foundation.Process, SystemPackage.FileDescriptor

**Storage**: No changes — `ConnectionTestResult` is ephemeral (`@State` in SwiftUI view only)

**Testing**: XCTest — unit test `ConnectionTester` with a mock process; manual testing via quickstart scenarios

**Target Platform**: macOS 13+ (menu bar app)

**Project Type**: macOS desktop/menubar app

**Performance Goals**: Test completes in under 10s for a healthy server; hard timeout at 15s

**Constraints**: Must not modify stored config or agent assignments; stdio only; no background polling

**Scale/Scope**: Single-user, single-machine; at most one test running at a time per view

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | ✅ Pass | SwiftUI button + inline result; uses native async/await concurrency |
| II. Single Source of Truth | ✅ Pass | Test is read-only; config unchanged |
| III. Non-Destructive Configuration | ✅ Pass | No config writes; no agent assignment changes |
| IV. Config Portability | ✅ N/A | Not a config feature |
| V. Simplicity & Discoverability | ✅ Pass | One button added to existing view; hidden for HTTP servers |

No gate violations.

## Project Structure

### Documentation (this feature)

```text
specs/008-mcp-connection-test/
├── plan.md              ← this file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
└── checklists/
    └── requirements.md
```

### Source Code (modified / new files)

```text
mcp-inator/
├── Services/
│   └── ConnectionTester.swift          ← NEW: actor; test lifecycle management
├── Models/
│   └── ConnectionTestResult.swift      ← NEW: ephemeral result type
└── UI/
    └── AddEditConfigView.swift          ← MODIFIED: test button + result display
```

**No new database tables. No new adapters. No new agent config changes.**

## Implementation Notes

### ConnectionTester (new actor)

```
actor ConnectionTester
  func test(config: MCPServerConfig) async -> ConnectionTestResult
    1. Record start time
    2. Launch Process(command, args, envVars); capture stderr pipe
    3. Create StdioTransport(input: process stdout fd, output: process stdin fd)
    4. Race: withThrowingTaskGroup
       - arm A: Client(info:...).connect(transport:) → success
       - arm B: Task.sleep(for: .seconds(15)) → timeout
    5. Catch launch errors (Process throws before connect)
    6. Classify result → ConnectionTestResult
    7. Cleanup: client.disconnect(), process.terminate(), close pipes
```

### ConnectionTestResult (new model)

```
enum ConnectionTestResult
  case success(elapsedSeconds: Double)
  case launchError(detail: String)
  case protocolError(detail: String)
  case timeout
```

### AddEditConfigView changes

- Add `@State private var testResult: ConnectionTestResult?`
- Add `@State private var isTesting: Bool`
- Add `ConnectionTester` instance (created once per view)
- Show "Test Connection" button only when `!isHTTP && !command.isEmpty`
- Button triggers `Task { isTesting = true; testResult = await tester.test(config: current); isTesting = false }`
- Below button: show `ConnectionTestResultView` when `testResult != nil`
- `ConnectionTestResultView`: small inline row — green checkmark + time on success; red × + message on failure

### Sparkle quarantine fix (already on main, include in this PR)

`mcp_inatorApp.swift` already has the `SparkleDelegate.willInstallUpdate` quarantine strip — this change is unstaged and will be committed with this branch.

## Complexity Tracking

No constitution violations to justify.
