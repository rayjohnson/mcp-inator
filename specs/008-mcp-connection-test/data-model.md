# Data Model: MCP Server Connection Test

## ConnectionTestResult

Ephemeral value type representing the outcome of a single connection test. Not persisted to disk or database.

```
ConnectionTestResult
├── status: TestStatus  (success | launchError | protocolError | timeout)
├── elapsedSeconds: Double?   (populated on success only)
├── errorDetail: String?      (populated on failure; includes stderr / exit code when available)
└── testedAt: Date            (timestamp of when the test completed)
```

### TestStatus values

| Value | Meaning |
|-------|---------|
| `success` | MCP initialize handshake completed successfully |
| `launchError` | Process could not be started (bad path, permission error, missing binary) |
| `protocolError` | Process started but threw before completing the handshake |
| `timeout` | 15 seconds elapsed without a completed handshake |

### Relationships

- `ConnectionTestResult` is derived from `MCPServerConfig` (read-only — the test never modifies the config).
- The result is held in transient `@State` in `AddEditConfigView`; it is discarded when the view is dismissed.

## No schema changes

This feature requires no new database tables or migrations. `MCPServerConfig` is unchanged.
