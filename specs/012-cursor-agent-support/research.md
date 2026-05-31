# Research: Cursor Agent Support

## Config Format

**Decision**: Cursor uses `{"mcpServers": {...}}` — identical to Claude Desktop.

**Rationale**: Cursor's documentation and community confirms the same JSON schema.
No adapter-level parsing differences; `JSONAdapterHelper` works unchanged.

**Alternatives considered**: None — format is fixed by Cursor, not our choice.

---

## Config File Path

**Decision**: `~/.cursor/mcp.json` (global, user-level config).

**Rationale**: Both Cursor IDE and Cursor CLI read this single file. Per-project
`.cursor/mcp.json` is out of scope (spec FR-010).

**Discovery rule**: Consider Cursor installed if `~/.cursor/mcp.json` exists OR
`~/.cursor/` directory exists (same pattern as ClaudeDesktopAdapter which checks
both file and parent dir).

**Alternatives considered**: Check `/Applications/Cursor.app` existence — rejected
because the spec explicitly says presence of config directory is sufficient (users
who uninstalled Cursor but kept their config should still be manageable).

---

## Cursor CLI vs Cursor IDE

**Decision**: Single `CursorAdapter` covers both.

**Rationale**: Cursor CLI and Cursor IDE share `~/.cursor/mcp.json`. No divergence
in format or path exists. A separate `CursorCLIAdapter` would be identical and
adds no value (spec FR-011).

**Alternatives considered**: Separate adapters — rejected per spec.

---

## Icon Strategy

**Decision**: `LetterBadge(letter: "C", background: dark charcoal)` as primary;
attempt `NSWorkspace` lookup for `"com.todesktop.230313mzl4w4u92"` (Cursor's
bundle ID on macOS) for the real app icon.

**Rationale**: Cursor's macOS bundle ID is `com.todesktop.230313mzl4w4u92` (Electron/Todesktop
wrapper). `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` can load the
actual icon at runtime, matching the pattern used by `ClaudeAppIcon` and
`GeminiDesktopAppIcon`. Fallback ensures display even when Cursor isn't installed.

**Alternatives considered**: Static asset in Assets.xcassets — requires obtaining/packaging
a Cursor icon asset and adds binary bloat; runtime lookup is cleaner.

---

## Database Migration

**Decision**: No migration required.

**Rationale**: `AgentType` is stored as a raw String in SQLite. Adding `.cursor = "cursor"`
is backward-compatible: existing rows don't have this value, and new rows will write
`"cursor"`. The fallback `?? .claudeCode` in `AgentRecord.init(row:)` covers unknown
values from newer DB versions opened by older app versions.

**Alternatives considered**: A formal migration (alter table / insert default row) — not
needed because `AgentType` enum cases don't correspond to rows, only to the `agentType`
column's string value.

---

## Key Validation

**Decision**: Same `^[a-z0-9][a-z0-9-]*$` rule as `ClaudeDesktopAdapter`.

**Rationale**: Cursor's `mcpServers` keys follow the same naming conventions as Claude's.
The rule is already shared across adapters and is enforced consistently.

**Alternatives considered**: Looser validation to handle underscore keys from existing
Cursor configs — spec edge-case says surface a warning; existing rule + `KeyValidationResult.invalid`
already does this.

---

## Test Fixtures

**Decision**: Reuse the `claude_desktop_config.json` fixture pattern; create a new
`cursor_mcp.json` test fixture with 2–3 server entries.

**Rationale**: Same format means same fixture structure. A separate named fixture
makes test intent clear and avoids cross-test coupling.

**Alternatives considered**: Reuse Claude Desktop fixture — workable but muddies
test provenance.
