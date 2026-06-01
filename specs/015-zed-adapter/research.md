# Research: Zed Editor MCP Adapter

## Zed Config Format

**Decision**: Use `context_servers` as the top-level key in `~/.config/zed/settings.json`, with a nested `command` object containing `path` and `args`.

**Rationale**: This is Zed's documented MCP configuration format. Unlike all existing adapters (which use a flat `{ "command": "...", "args": [...] }` structure under various top-level keys), Zed nests the command: `{ "command": { "path": "...", "args": [...] }, "env": {...} }`. The internal `MCPServerConfig` model maps cleanly: `command` → `path`, `args` → `args`, `envVars` → `env`.

**Alternatives considered**: Reusing `FileBasedAdapter` with a flag for format variant — rejected because the entry serialization difference is significant enough to warrant a dedicated adapter class, consistent with `ClaudeCodeAdapter` which also has a custom format.

---

## Installation Detection

**Decision**: Detect Zed as installed when `~/.config/zed/settings.json` exists, `~/.config/zed/` directory exists, OR `/Applications/Zed.app` is present.

**Rationale**: A fresh Zed install creates the `~/.config/zed/` directory before settings.json exists. The app bundle check allows detection even before first launch. This mirrors how `ClaudeCodeAdapter` checks for both `~/.claude.json` and the `~/.claude/` directory.

**Alternatives considered**: App bundle only — rejected because a headless/CI install without the app bundle would not be detected. Settings file only — rejected because Zed creates the directory before any settings file.

---

## Adapter Architecture

**Decision**: Implement `ZedAdapter` as a dedicated struct conforming to `AgentAdapter`, similar to `ClaudeCodeAdapter`. Reuse `JSONAdapterHelper.readFullJSON`, `checkDrift`, and `writeAtomic` but implement Zed-specific entry parsing and serialization inline.

**Rationale**: `FileBasedAdapter` delegates entry parsing/serialization entirely to `JSONAdapterHelper.parseMCPConfigs` and `serializeConfig`, which use the standard flat format. Zed's nested `command` object requires different parsing logic. Rather than adding a format flag to `FileBasedAdapter` (which would complicate a simple generic adapter), a dedicated `ZedAdapter` keeps the format-specific code isolated and easy to test.

**Alternatives considered**: Extend `JSONAdapterHelper` with a Zed format variant — rejected because it adds conditional logic to a helper that is currently unconditional and clean.

---

## Server Key Validation

**Decision**: Accept any non-empty alphanumeric-and-hyphen string. Use the same `^[a-z0-9][a-z0-9-]*$` pattern as Cursor/Claude Desktop for consistency, since Zed has no documented restrictions stricter than that.

**Rationale**: Zed's documentation does not specify key naming restrictions. Applying the same conservative pattern used by other adapters prevents invalid JSON keys while being permissive enough for real-world server names.

**Alternatives considered**: Accepting any non-empty string — rejected in favor of consistency with other adapters and to prevent accidental whitespace or special character keys.

---

## Test Coverage

**Decision**: Add `ZedAdapterTests.swift` in `mcp-inatorTests/Integration/` following the `CursorAdapterTests` pattern. Add a `zed_settings.json` fixture with at least two entries. Cover: read from fixture, write creates file, preserves unknown keys, drift detection, remove, isInstalled detection paths.

**Rationale**: The Zed adapter has a distinct config format — a fixture-based integration test is the right level to verify the full read/write/round-trip behavior. Unit tests for `isInstalled()` use the injectable `homeDirectory` pattern from `ClaudeCodeAdapter`.
