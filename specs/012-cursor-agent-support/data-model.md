# Data Model: Cursor Agent Support

## Changed Entities

### AgentType (enum, `mcp-inator/Models/AgentRecord.swift`)

Add one case. No other fields change.

| Field | Before | After |
|-------|--------|-------|
| `.cursor` case | absent | `case cursor = "cursor"` |
| `displayName` | — | add `.cursor: return "Cursor"` |
| `isAppManaged` | — | `.cursor` → `false` (default) |
| `defaultConfigPath` | — | add `.cursor: return "\(home)/.cursor/mcp.json"` |

**Backward compatibility**: Raw value `"cursor"` is new; existing DB rows are
unaffected. Unknown raw values still fall back to `.claudeCode` via the `?? .claudeCode`
guard in `AgentRecord.init(row:)`. No migration needed.

---

## New Entities

### CursorAdapter (struct, `mcp-inator/Adapters/CursorAdapter.swift`)

Conforms to `AgentAdapter`. Identical contract to `ClaudeDesktopAdapter` with
different `agentType` and `defaultConfigPath`.

| Property / Method | Value / Behaviour |
|-------------------|-------------------|
| `agentType` | `.cursor` |
| `displayName` | `"Cursor"` |
| `defaultConfigPath()` | `~/.cursor/mcp.json` (via `FileManager.homeDirectoryForCurrentUser`) |
| `isInstalled()` | `true` if `~/.cursor/mcp.json` exists OR `~/.cursor/` directory exists |
| `readConfigs(from:)` | `JSONAdapterHelper.readFullJSON` → parse `mcpServers` key |
| `writeConfigs(_:to:expectedExisting:)` | `JSONAdapterHelper.writeConfigs` with `mcpKey: "mcpServers"` |
| `removeConfig(key:from:expectedValue:)` | `JSONAdapterHelper.removeConfig` with `mcpKey: "mcpServers"` |
| `validateServerKey(_:)` | `^[a-z0-9][a-z0-9-]*$` — same as `ClaudeDesktopAdapter` |
| `isAppManaged` | `false` (default from protocol extension) |

---

## UI Changes

### AgentIcon (view, `mcp-inator/UI/AgentIcon.swift`)

Add one case to the `switch agentType` block:

```swift
case .cursor:
    CursorAppIcon()
```

`CursorAppIcon` follows the same pattern as `GeminiDesktopAppIcon`:
- Attempt `NSWorkspace` lookup for bundle ID `"com.todesktop.230313mzl4w4u92"`
- Try `/Applications/Cursor.app` path as fallback
- Fall back to `LetterBadge(letter: "C", background: Color(red: 0.07, green: 0.07, blue: 0.07))`
  (dark charcoal — matches Cursor's brand color)

---

## Registration Points

Both arrays must include `CursorAdapter()`:

| File | Change |
|------|--------|
| `mcp-inator/App/mcp_inatorApp.swift` | Add `CursorAdapter()` to `adapters` array |
| `mcp-inator/UI/MenuBarView.swift` | Add `CursorAdapter()` to `allAdapters` computed property |

---

## Test Fixture

New file: `mcp-inatorTests/Fixtures/cursor_mcp.json`

```json
{
  "mcpServers": {
    "github-mcp": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_placeholder" }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
    }
  }
}
```

---

## Validation Rules

| Rule | Source |
|------|--------|
| Server key: `^[a-z0-9][a-z0-9-]*$` | `CursorAdapter.validateServerKey` |
| File must be valid JSON if it exists | `JSONAdapterHelper.readFullJSON` — throws `AdapterError.parseFailure` |
| Drift detection on write/remove | `JSONAdapterHelper.checkDrift` — returns `.driftDetected` WriteResult |
