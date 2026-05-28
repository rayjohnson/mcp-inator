# Research: MCP Server Connection Test

## MCP Swift SDK — Client API

**Decision**: Use `Client.connect(transport:)` from the bundled `modelcontextprotocol/swift-sdk` for the handshake.

**Rationale**: `Client.connect(transport:)` performs the full MCP `initialize`/`initialized` exchange and returns an `Initialize.Result`. This is the correct semantic test — if it succeeds, the server speaks MCP correctly. If it throws, it doesn't. No need to re-implement JSON-RPC parsing.

**API surface needed**:
```swift
// Connect and perform initialize handshake
let result: Initialize.Result = try await client.connect(transport: transport)
// Disconnect cleanly
await client.disconnect()
```

**Alternatives considered**: Manually write JSON-RPC `initialize` to the process's stdin and parse the response — rejected because it duplicates the SDK's logic and is fragile to protocol changes.

---

## Process Spawning for stdio Servers

**Decision**: Use `Foundation.Process` to launch the server, with `Pipe` for stdin/stdout. Convert `Pipe.fileHandleForReading.fileDescriptor` to `SystemPackage.FileDescriptor` for `StdioTransport`.

**Rationale**: `StdioTransport` in the swift-sdk takes `SystemPackage.FileDescriptor` values. `Process` + `Pipe` is the standard Foundation approach; converting `Int32` → `FileDescriptor(rawValue:)` is straightforward.

**Key details**:
- Stderr pipe should be captured separately so we can include it in error messages.
- `Process.terminationStatus` is available after the process exits — useful for "process exited with code N" errors.
- Process must be terminated and all pipes closed in the cleanup path to avoid leaks.

**Alternatives considered**: Using `NSTask` (same thing, older name); using a shell wrapper — rejected as unnecessary complexity.

---

## Timeout Strategy

**Decision**: Wrap the `Client.connect()` call in `withThrowingTaskGroup` with a `.sleep(for: .seconds(15))` racing arm. Cancel the group when either arm completes first.

**Rationale**: Swift Structured Concurrency task groups are the idiomatic way to implement racing timeouts. `Task.sleep` is cancellable, so the timeout arm cleans up correctly if the connect succeeds early.

**Alternatives considered**: `withTimeout` from third-party libraries — not available; `DispatchSemaphore` — pre-concurrency pattern, doesn't compose with `async/await`.

---

## Error Classification

**Decision**: Three distinct failure categories communicated to the UI:

| Category | Condition | User-facing message style |
|----------|-----------|--------------------------|
| Launch error | Process fails to start (bad path, missing binary) | "Could not launch: <stderr or OS error>" |
| Protocol error | Process starts but `connect()` throws before timeout | "Server started but did not respond to MCP handshake: <error>" |
| Timeout | 15 seconds elapse without a response | "Server did not respond within 15 seconds" |

**Rationale**: Maps directly to FR-005's requirement to distinguish failure types. Matches spec acceptance scenarios.

---

## UI Integration Point

**Decision**: Add the test button inline in `AddEditConfigView`, visible only when `transportType == .stdio` and `command` is non-empty. Display the result below the button.

**Rationale**: `AddEditConfigView` is the only server detail view. Showing the result there — where the user just configured the command — gives immediate feedback. HTTP/SSE servers are out of scope per spec assumptions.

**Alternatives considered**: A separate "Server Detail" read-only view — doesn't exist yet; adding to `ConfigLibraryView` list rows — too small, no room for result display.
