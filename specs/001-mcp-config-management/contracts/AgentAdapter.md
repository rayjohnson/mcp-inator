# Contract: AgentAdapter Protocol

**Date**: 2026-05-25 | **Plan**: [../plan.md](../plan.md) | **Research**: [../research.md](../research.md)

This document defines the contract every agent adapter must satisfy. Each concrete adapter
(`ClaudeCodeAdapter`, `ClaudeDesktopAdapter`, `GeminiCLIAdapter`, `CodexCLIAdapter`) implements
this protocol. The rest of the app interacts only with `AgentAdapter` — never with concrete types.

---

## Protocol Definition

```swift
/// Encapsulates all format- and path-specific logic for one supported AI tool.
/// Implementations MUST be stateless and re-entrant — all state lives in the database
/// or on disk, not in the adapter instance.
protocol AgentAdapter {

    // MARK: - Identity

    /// Stable type identifier matching AgentRecord.agentType.
    var agentType: AgentType { get }

    /// Human-readable name shown in the UI, e.g. "Claude Code".
    var displayName: String { get }

    // MARK: - Path Resolution

    /// Returns the default absolute path to the agent's config file.
    /// Called during discovery and when isCustomPath == false.
    func defaultConfigPath() -> URL

    // MARK: - Discovery

    /// Returns true if the agent appears to be installed.
    /// Checks: config file exists OR parent directory exists.
    /// Must NOT throw — return false on any I/O error.
    func isInstalled() -> Bool

    // MARK: - Reading

    /// Reads all MCP server entries from the config file at `path`.
    /// Returns an empty dict if the file does not exist (not an error).
    /// Throws `AdapterError.parseFailure` if the file exists but cannot be parsed.
    func readConfigs(from path: URL) throws -> [String: MCPServerConfig]

    // MARK: - Writing

    /// Atomically writes the full set of enabled configs to the config file at `path`.
    ///
    /// Contract:
    /// - Reads the current on-disk content first (pre-flight, FR-023)
    /// - Pre-flight scope: compare ONLY the keys present in `expectedExisting` against
    ///   the same keys on disk. Keys in the file that are NOT in `expectedExisting`
    ///   (i.e., entries mcp-inator doesn't manage) are IGNORED in the comparison —
    ///   their presence never triggers `.driftDetected`. This prevents a user's manually
    ///   added entries from causing spurious drift alerts on every write.
    /// - If any key in `expectedExisting` has a different value on disk (or is missing),
    ///   returns `.driftDetected` without writing; caller shows diff UI
    /// - `expectedExisting` should be the `lastWrittenSnapshot` from ConfigAgentAssignment,
    ///   NOT the current DB values — these diverge when a user edits a config and declines
    ///   propagation (DB updated, file still has old values).
    /// - Merges `configs` into existing file content (preserves unrelated keys)
    /// - Writes via temp file + atomic rename (FR-027)
    /// - Creates parent directory if missing
    ///
    /// Returns `.success` or `.driftDetected(onDisk:expected:)`.
    /// Throws `AdapterError.writeFailure` on I/O errors.
    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult

    /// Removes a single config entry (by server key) from the config file at `path`.
    /// Atomically rewrites the file with the entry absent.
    /// No-op if the key is not present.
    ///
    /// Pre-flight: reads the current on-disk value for `key` and compares it to
    /// `expectedValue`. If they differ (entry was externally modified), returns
    /// `.driftDetected` without writing. Pass `nil` to skip the pre-flight check.
    ///
    /// Throws `AdapterError.writeFailure` on I/O errors.
    func removeConfig(
        key: String,
        from path: URL,
        expectedValue: MCPServerConfig?
    ) throws -> WriteResult

    // MARK: - Validation

    /// Validates `serverKey` against this agent's constraints.
    /// Returns `.valid` or `.invalid(reason:)`.
    /// Called before enable (FR-024).
    func validateServerKey(_ key: String) -> KeyValidationResult
}
```

---

## Supporting Types

```swift
enum WriteResult {
    /// Write completed successfully.
    case success

    /// On-disk content differs from expected — write was NOT performed.
    /// `onDisk` is what the file currently contains.
    /// `expected` is what the caller believed was on disk.
    case driftDetected(onDisk: [String: MCPServerConfig], expected: [String: MCPServerConfig])
}

enum KeyValidationResult {
    case valid
    case invalid(reason: String)
}

enum AdapterError: Error {
    /// Config file exists but could not be parsed.
    case parseFailure(URL, underlying: Error)

    /// File I/O error during write.
    case writeFailure(URL, underlying: Error)
}
```

---

## Concrete Adapter Responsibilities

### ClaudeCodeAdapter

- **Format**: JSON, key `mcpServers`
- **Default path**: `~/.claude.json`
- **Key validation**: reject `"workspace"` (reserved); reject keys not matching `[a-z0-9][a-z0-9-]*`
- **Round-trip**: preserve all keys in `~/.claude.json` outside `mcpServers`

### ClaudeDesktopAdapter

- **Format**: JSON, key `mcpServers`
- **Default path**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Key validation**: standard rule only
- **Round-trip**: preserve all keys in the file outside `mcpServers`

### GeminiCLIAdapter

- **Format**: JSON, key `mcpServers`
- **Default path**: `~/.gemini/settings.json`
- **Key validation**: reject keys containing `_` (Gemini constraint); standard rule otherwise
- **Round-trip**: preserve all keys in the file outside `mcpServers`

### CodexCLIAdapter

- **Format**: TOML, section `mcp_servers`
- **Default path**: `~/.codex/config.toml`
- **Key validation**: standard rule only (underscores are OK in Codex)
- **Round-trip**: preserve all TOML keys outside `mcp_servers`
- **Dependency**: TOMLKit for TOML parsing/serialization

---

## Invariants (all adapters must uphold)

1. **Stateless**: No instance variables that persist between calls.
2. **Atomic writes**: All writes use temp file + atomic rename (FR-027). Never write directly to the target path.
3. **Preserve unrelated content**: A file containing settings beyond `mcpServers` (or `mcp_servers`) must have those settings intact after any write.
4. **Empty file creation**: If the config file does not exist, `writeConfigs` creates it with only the `mcpServers` / `mcp_servers` section populated.
5. **Pre-flight check**: `writeConfigs` MUST compare on-disk state to `expectedExisting` before writing. If they differ, return `.driftDetected` — do not write.
6. **Directory creation**: If the parent directory does not exist, create it (with intermediate directories) before writing.
7. **Error isolation**: Parse failures on one key must not prevent reading/writing other keys where possible.

---

## Integration Test Contract

Each adapter has a corresponding integration test suite in `mcp-inatorTests/Integration/`:

```
<AgentName>AdapterTests.swift
```

Each test suite MUST cover:

| Test case | What it verifies |
|-----------|-----------------|
| `testRead_emptyFile` | Returns empty dict for missing file |
| `testRead_validFixture` | Parses fixture file; fields match expected values |
| `testRead_preservesUnknownKeys` | Non-mcpServers keys survive a read-write round-trip |
| `testWrite_createsFileIfMissing` | Creates file + parent dir; content is correct |
| `testWrite_mergesIntoExistingFile` | Adds new key without disturbing existing keys |
| `testWrite_removesDisabledConfig` | `removeConfig` deletes the key; file still valid |
| `testWrite_removeConfig_driftDetected` | `removeConfig` returns `.driftDetected` when on-disk != expectedValue |
| `testWrite_atomicOnCrash` | Write to read-only dir throws `writeFailure`; no partial file |
| `testWrite_driftDetected_managedKeyOnly` | Returns `.driftDetected` only when a key in `expectedExisting` differs; unmanaged keys in file do NOT trigger drift |
| `testValidateServerKey_valid` | Returns `.valid` for conforming key |
| `testValidateServerKey_invalid` | Returns `.invalid` for agent-specific violations |

Fixture files live in `mcp-inatorTests/Integration/Fixtures/`:
- `claude_code_config.json`
- `claude_desktop_config.json`
- `gemini_config.json`
- `codex_config.toml`
