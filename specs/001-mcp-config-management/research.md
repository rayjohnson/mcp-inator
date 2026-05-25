# Phase 0 Research: MCP Server Configuration Management

**Date**: 2026-05-25 | **Plan**: [plan.md](plan.md)

All NEEDS CLARIFICATION items from the Technical Context are resolved here.

---

## R-001: Per-Agent Server Key Format Constraints

**Decision**: Use lowercase-hyphenated rule as default (spaces→hyphens, strip non-alphanumeric-and-hyphen). Enforce per-adapter validation at enable-time for agents with additional constraints.

**Findings**:

| Agent | Key format | Constraints | Reserved names |
|-------|-----------|-------------|----------------|
| Claude Code CLI | Any string | None documented | `workspace` (reserved) |
| Claude Desktop | Any string | None documented | None found |
| Gemini CLI | Alphanumeric + hyphen | **No underscores allowed** | None found |
| Codex CLI | Alphanumeric + underscore + hyphen | None documented | None found |

**Auto-population rule** (N-001): `lowercase(displayName)` → replace spaces with `-` → strip characters that are not `[a-z0-9-]`. Always user-editable before saving.

**Per-adapter validation**:
- `GeminiCLIAdapter`: reject server keys containing `_`; show validation error pre-write
- `ClaudeCodeAdapter`: reject key `workspace`; treat as FR-024 conflict
- Others: no additional constraints beyond the auto-population rule

**Rationale**: Gemini's constraint is undocumented but observed in practice; our default rule (hyphens only) is already compliant. The `workspace` reservation in Claude Code is documented in the Claude Code CLI source.

**Alternatives considered**: Enforce strictest common subset across all agents at library level. Rejected — too restrictive and prevents valid configs for agents that allow more characters.

---

## R-002: macOS Sandbox Policy

**Decision**: Distribute **unsandboxed** via GitHub Releases and Homebrew cask. Use Developer ID signing + Hardened Runtime + notarization + stapling.

**Findings**:
- App Store distribution requires sandbox; GitHub/Homebrew distribution does not.
- `~/Library/Application Support/` is **not** TCC-protected. An unsandboxed, notarized app can read and write this path freely without user prompts.
- Agent config file locations:
  - `~/.claude.json` — user home, writable by any process running as that user
  - `~/Library/Application Support/Claude/claude_desktop_config.json` — not TCC-gated
  - `~/.gemini/settings.json` — user home, writable
  - `~/.codex/config.toml` — user home, writable
- No Security-Scoped Bookmarks, NSOpenPanel flows, or entitlement negotiation required.
- Hardened Runtime is required for notarization; `com.apple.security.get-task-allow` must be `false` in production.

**Implications for FR-021** (custom path override): NSOpenPanel is not required for security purposes in the unsandboxed case. It may still be used for UX (browsing) but is not mandatory.

**Signing requirements** (constitution-mandated):
1. Developer ID Application certificate (Keychain access, $99/yr Apple Developer Program)
2. Hardened Runtime enabled in Xcode project settings
3. `xcrun notarytool submit <pkg> --wait` after build
4. `xcrun stapler staple <app>` to attach ticket

**Rationale**: Unsandboxed is the standard approach for developer tools distributed outside the App Store. The paths mcp-inator needs to write are all accessible without elevated permissions.

---

## R-003: Agent Config Formats

### Claude Code CLI

- **Default config path**: `~/.claude.json` (user scope)
- **Project-scoped path**: `.mcp.json` (workspace root, not managed by mcp-inator in Spec 001)
- **Format**: JSON
- **MCP servers key**: `mcpServers`
- **Server entry structure**:
  ```json
  {
    "mcpServers": {
      "<server-name>": {
        "command": "<executable>",
        "args": ["<arg1>", "<arg2>"],
        "env": {
          "<KEY>": "<value>"
        }
      }
    }
  }
  ```
  Also supports `"type": "http"` with `"url"` for remote HTTP servers (out of scope for Spec 001 — stdio only).
- **Reserved server name**: `workspace` — must not be written as a user-defined key (FR-024)
- **Restart required**: Yes — Claude Code CLI reads config on startup; must restart the CLI session

### Claude Desktop

- **Config path**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Format**: JSON
- **MCP servers key**: `mcpServers`
- **Server entry structure**:
  ```json
  {
    "mcpServers": {
      "<server-name>": {
        "command": "<executable>",
        "args": ["<arg1>"],
        "env": {
          "<KEY>": "<value>"
        }
      }
    }
  }
  ```
  No `type` field — stdio only.
- **Restart required**: Yes — full application restart required (quit and reopen from menubar)

### Gemini CLI

- **Config path**: `~/.gemini/settings.json`
- **Format**: JSON
- **MCP servers key**: `mcpServers`
- **Server entry structure**:
  ```json
  {
    "mcpServers": {
      "<server-name>": {
        "command": "<executable>",
        "args": ["<arg1>"],
        "env": {
          "<KEY>": "<value>"
        }
      }
    }
  }
  ```
- **Key constraint**: **No underscores** — server names must match `[a-z0-9-]+`
- **Restart required**: Yes — `gemini` process restart OR `/mcp reload` command inside an active session (FR-022 notification text should mention both options)

### Codex CLI

- **Config path**: `~/.codex/config.toml`
- **Format**: **TOML** (not JSON)
- **Server entry structure**:
  ```toml
  [mcp_servers.<server-id>]
  command = "<executable>"
  args = ["<arg1>"]

  [mcp_servers.<server-id>.env]
  KEY = "value"
  ```
- **Key constraint**: TOML table key rules — alphanumeric, hyphens, underscores allowed; avoid dots and spaces
- **Restart required**: Yes — `codex` process restart required

**Implication**: `CodexCLIAdapter` must implement TOML read/write, not JSON. A lightweight Swift TOML library (e.g. [TOMLKit](https://github.com/LebJe/TOMLKit)) or manual serialization is required. This adapter is the most complex of the four.

---

## R-004: Agent Restart Behavior

**Decision**: All four agents require a process restart to pick up config file changes. FR-022 notification fires after every write.

**Findings**:

| Agent | Reload mechanism | Notes |
|-------|-----------------|-------|
| Claude Code CLI | Process restart | No hot-reload; new CLI invocations pick up changes |
| Claude Desktop | Full app restart | Quit from menu bar → reopen |
| Gemini CLI | Process restart OR `/mcp reload` | In-session reload is possible but unreliable |
| Codex CLI | Process restart | No documented hot-reload |

**Notification text recommendation**: "Restart [Agent Name] to apply changes." For Gemini, append "(or run `/mcp reload` in an active session)."

---

## R-005: GRDB Schema Design Guidance

**Decision**: Use GRDB 6.x with explicit migration records. Three tables: `mcp_server_configs`, `agents`, `config_agent_assignments`.

**Key findings**:
- GRDB 6.x supports Swift Codable conformance via `FetchableRecord` + `PersistableRecord`
- Migrations are registered in order; GRDB tracks `grdb_migrations` table automatically
- Recommended pattern: `DatabaseMigrator` with numbered migrations in `Migrations/` directory
- JSON columns (env vars, args) should be stored as `TEXT` with JSON serialization; GRDB does not natively serialize arrays/dicts
- SQLite `INTEGER` for booleans; `TEXT` for enums (stored as raw string values)

---

## R-006: Atomic File Write Pattern (Swift)

**Decision**: Write to a temp file in the same directory, then `FileManager.replaceItem(at:withItemAt:)` for atomic rename.

**Pattern**:
```swift
// 1. Write to temp file in same directory (ensures same filesystem = atomic rename)
let tempURL = targetURL.deletingLastPathComponent()
    .appendingPathComponent(UUID().uuidString + ".tmp")
try data.write(to: tempURL, options: .atomic)

// 2. Atomic replace
try FileManager.default.replaceItem(
    at: targetURL,
    withItemAt: tempURL,
    backupItemName: nil,
    resultingItemURL: nil
)
```

`FileManager.replaceItem` is the correct API (not `moveItem`) — it preserves metadata, handles existing-file replace atomically, and cleans up the temp file.

**Directory creation**: `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` before first write if config directory doesn't exist (e.g., `~/.gemini/`).

---

## R-007: TOML Handling in Swift

**Decision**: Use [TOMLKit](https://github.com/LebJe/TOMLKit) as a Swift Package Manager dependency for Codex TOML read/write.

**Rationale**: No TOML support in Foundation. TOMLKit is the most-starred pure-Swift TOML library, supports Swift 5.5+, has no C dependencies, and handles the subset of TOML needed (string keys, string/array values, nested tables).

**Alternative**: Manual TOML serialization. Rejected — fragile for the full TOML grammar even for a simple subset; TOMLKit is lightweight (~500 lines) and well-tested.

**Codex config merge strategy**: Read full TOML document → mutate `mcp_servers` section → write back. Preserves unrelated keys (Codex settings outside `mcp_servers`).

---

## Summary of Open Items from notes.md

| Item | Resolution |
|------|-----------|
| R-001: Per-agent key constraints | **Resolved** — Gemini: no underscores; Claude Code: `workspace` reserved |
| R-002: Duplicate key behavior | **Deferred** — no library-level uniqueness constraint; FR-024 handles at enable-time |
| R-003: Deletion cascade (unavailable agent) | **Resolved** — warn and proceed (partial delete); UI shows which agents updated vs. not |
| R-004: Agent restart behavior | **Resolved** — all 4 require restart; FR-022 fires always |
