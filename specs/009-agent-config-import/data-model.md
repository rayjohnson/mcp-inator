# Data Model: Import MCP Servers from Agent Config Files

**Feature**: 009-agent-config-import  
**Date**: 2026-05-29

## New Type: `ImportSource`

A transient, adapter-derived value representing one agent whose config can potentially be imported. Not persisted to the database.

**Location**: `mcp-inator/Models/ImportSource.swift` — `internal` access, visible to both UI and tests via `@testable import mcp_inator`.

| Field | Type | Description |
|-------|------|-------------|
| `displayName` | `String` | Human-readable agent name (e.g. "Claude Desktop") |
| `agentType` | `AgentType` | Enum case identifying the agent |
| `adapter` | `any AgentAdapter` | The adapter used to read the config file |
| `configPath` | `URL` | Resolved path to the agent's config file |
| `isImportable` | `Bool` | `true` = file-backed, readable; `false` = app-managed |
| `unavailableReason` | `String?` | Tooltip text shown when `!isImportable` |

**Construction rules**:
- Only created for installed agents (`adapter.isInstalled() == true`)
- `isImportable = false` when `adapter.isAppManaged == true`
- `isImportable = true` only when config file exists at `configPath`
- If not installed → not created (absent from list)

## New Type: `ImportSourceScanner`

A pure value-type service that produces `[ImportSource]` from a list of adapters. Keeping this logic out of the view makes it directly testable.

**Location**: `mcp-inator/Services/ImportSourceScanner.swift`

| Field | Type | Description |
|-------|------|-------------|
| `adapters` | `[any AgentAdapter]` | Adapters to scan; defaults to all five production adapters |
| `fileExists` | `(URL) -> Bool` | File-existence check; defaults to `FileManager.default.fileExists(atPath:)` |

**Method**: `func scan() -> [ImportSource]` — applies construction rules and returns the filtered list.

**Testability**: inject `StubAdapter` instances and a `{ _ in true/false }` closure to exercise every construction rule without touching the filesystem or requiring a running app.

## New Test Double: `StubAdapter`

**Location**: `mcp-inatorTests/TestHelpers/StubAdapter.swift` (test target only)

A configurable `AgentAdapter` conformer for use across all test suites. Replaces the need to copy `MockAdapter` per test file.

| Property | Default | Purpose |
|----------|---------|---------|
| `agentType` | `.claudeDesktop` | Identifies the adapter in assertions |
| `installedResult` | `true` | Controls `isInstalled()` return value |
| `appManagedResult` | `false` | Controls `isAppManaged` |
| `configPathResult` | `/dev/null` | Controls `defaultConfigPath()` |
| `readResult` | `[:]` | Controls `readConfigs(from:)` return value |

## Modified Type: `ConfigStore.applyImportDecisions`

No schema change. The existing method signature gains an optional `agentId`:

```
applyImportDecisions(_ decisions: [(key: String, config: MCPServerConfig)], agentId: Int64?) throws
```

**Behaviour change**:
- `agentId != nil` → existing behaviour: insert/update config + enable for agent (used by first-run discovery)
- `agentId == nil` → insert/update `MCPServerConfig` only; no `ConfigAgentAssignment` created (new import flow)

## Unchanged Types

The following existing types are used without structural change:

| Type | Role |
|------|------|
| `ConfigStore.ImportCategory` | `.new`, `.exactMatch`, `.conflict` — categorises each discovered entry |
| `MCPServerConfig` | Library record created/updated on import |
| `ConfigAgentAssignment` | Created only when `agentId != nil`; not touched by new import flow |
| `AgentAdapter` | Protocol; all existing adapters' `readConfigs(from:)` used as-is |
