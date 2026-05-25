# Data Model: MCP Server Configuration Management

**Date**: 2026-05-25 | **Plan**: [plan.md](plan.md) | **Research**: [research.md](research.md)

---

## Entities

### MCPServerConfig

The canonical representation of a single MCP server configuration. This is mcp-inator's primary record — agent config files are derived from it.

```swift
struct MCPServerConfig: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?                        // GRDB rowid
    let uuid: UUID                        // Stable external identity (UUID v4)
    var displayName: String               // Human-readable, shown only in mcp-inator UI
    var serverKey: String                 // JSON/TOML key used in agent config files
    var command: String                   // Executable path or URL
    var args: [String]                    // Ordered list of command arguments
    var envVars: [EnvVar]                 // Environment variable pairs
    var notes: String                     // Optional user notes (may be empty)
    let createdAt: Date
    var updatedAt: Date
}
```

**Validation rules**:
- `displayName`: non-empty, max 100 characters
- `serverKey`: matches `[a-z0-9][a-z0-9-]*` (auto-populated from displayName, user-editable); max 64 characters
- `command`: non-empty
- `args`: may be empty
- `envVars`: may be empty; each key non-empty

**Storage notes**:
- `args` stored as JSON text in SQLite: `["arg1","arg2"]`
- `envVars` stored as JSON text in SQLite (see EnvVar below)
- `uuid` stored as TEXT (UUID string representation)

---

### EnvVar

An individual environment variable entry. Supports both literal values and `${VAR_NAME}` references.

```swift
struct EnvVar: Codable, Equatable {
    var key: String          // Env var name, e.g. "GITHUB_TOKEN"
    var value: String        // Literal value OR "${VAR_NAME}" reference
    var isSensitive: Bool    // If true, mask in UI by default (reveal on demand)
}
```

**Sensitivity heuristic** (applied at add/import time, user-overridable):
- `isSensitive = true` if value does not match `^\$\{[A-Z_][A-Z0-9_]*\}$` (i.e., not a clean env var reference)
- `isSensitive = false` for env var references like `${GITHUB_TOKEN}` — the reference itself is not sensitive

---

### AgentRecord

A supported AI tool that mcp-inator has detected or manually registered.

```swift
struct AgentRecord: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let agentType: AgentType             // Enum identifying the adapter to use
    var displayName: String              // e.g. "Claude Code", "Gemini CLI"
    var configPath: String               // Resolved absolute path to config file
    var isCustomPath: Bool               // True if user overrode the default path
    var isAvailable: Bool                // True if config file exists or directory is writable
    let discoveredAt: Date
    var lastSeenAt: Date
}

enum AgentType: String, Codable, CaseIterable {
    case claudeCode     = "claude_code"
    case claudeDesktop  = "claude_desktop"
    case geminiCLI      = "gemini_cli"
    case codexCLI       = "codex_cli"
}
```

**Default config paths** (resolved at discovery time):
| AgentType | Default path |
|-----------|-------------|
| `claudeCode` | `~/.claude.json` |
| `claudeDesktop` | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| `geminiCLI` | `~/.gemini/settings.json` |
| `codexCLI` | `~/.codex/config.toml` |

**Availability**: An agent is `isAvailable = true` when its config file exists OR its parent directory exists and is writable (mcp-inator will create the file on first enable).

---

### ConfigAgentAssignment

The relationship between a config and an agent, including enable/disable state.

```swift
struct ConfigAgentAssignment: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let configUUID: UUID                 // FK → MCPServerConfig.uuid
    let agentId: Int64                   // FK → AgentRecord.id
    var state: AssignmentState
    var assignedAt: Date
    var updatedAt: Date
}

enum AssignmentState: String, Codable {
    case enabled    = "enabled"
    case disabled   = "disabled"
}
```

**Notes**:
- No `pending` state — deferred propagation is surfaced by FR-023 pre-flight diff check on next write
- `unavailable` is a computed property derived from `AgentRecord.isAvailable`, not a stored state
- Unique constraint: `(configUUID, agentId)` — one assignment record per config+agent pair

---

## SQLite Schema (GRDB Migrations)

### Migration 001 — Initial Schema

```sql
CREATE TABLE mcp_server_configs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid        TEXT    NOT NULL UNIQUE,
    displayName TEXT    NOT NULL,
    serverKey   TEXT    NOT NULL,
    command     TEXT    NOT NULL,
    args        TEXT    NOT NULL DEFAULT '[]',   -- JSON array
    envVars     TEXT    NOT NULL DEFAULT '[]',   -- JSON array of EnvVar objects
    notes       TEXT    NOT NULL DEFAULT '',
    createdAt   REAL    NOT NULL,                -- Unix timestamp
    updatedAt   REAL    NOT NULL
);

CREATE TABLE agents (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    agentType     TEXT    NOT NULL,
    displayName   TEXT    NOT NULL,
    configPath    TEXT    NOT NULL,
    isCustomPath  INTEGER NOT NULL DEFAULT 0,    -- 0=false, 1=true
    isAvailable   INTEGER NOT NULL DEFAULT 1,
    discoveredAt  REAL    NOT NULL,
    lastSeenAt    REAL    NOT NULL
);

CREATE TABLE config_agent_assignments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    configUUID  TEXT    NOT NULL REFERENCES mcp_server_configs(uuid) ON DELETE CASCADE,
    agentId     INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    state       TEXT    NOT NULL DEFAULT 'disabled',
    assignedAt  REAL    NOT NULL,
    updatedAt   REAL    NOT NULL,
    UNIQUE(configUUID, agentId)
);

CREATE INDEX idx_assignments_configUUID ON config_agent_assignments(configUUID);
CREATE INDEX idx_assignments_agentId    ON config_agent_assignments(agentId);
```

---

## State Transitions

### Config-Agent Assignment State Machine

```
[no record]
     │
     │ user enables config for agent
     ▼
  enabled ──────────────────────────► disabled
     │     user disables              │
     │                                │ user enables
     └────────────────────────────────┘

  (unavailable = computed from AgentRecord.isAvailable; not a stored state)
```

- **Enable**: creates assignment record with `state = enabled`; writes config to agent file; fires FR-022 restart notification
- **Disable**: sets `state = disabled`; removes config key from agent file; fires FR-022 restart notification
- **Delete config**: cascades — all assignments deleted; config key removed from all enabled-agent files

### AgentRecord Availability

```
  isAvailable = false
       │
       │ config file created / directory becomes writable
       ▼
  isAvailable = true
       │
       │ config file / directory removed
       ▼
  isAvailable = false
```

Availability is refreshed on: app launch, popover open, before any write operation.

---

## Derived Data (not stored)

These are computed at runtime and never persisted:

- **Effective enabled configs per agent**: `JOIN mcp_server_configs ON config_agent_assignments WHERE state = 'enabled' AND agents.isAvailable = true`
- **Conflict detection** (FR-024): server keys of enabled configs for the same agent — checked before enable
- **Pre-flight diff** (FR-023): on-disk agent config read and compared to what mcp-inator would write — computed immediately before each write

---

## JSON / TOML Mapping

### JSON agents (Claude Code, Claude Desktop, Gemini CLI)

Agent config file shape:
```json
{
  "mcpServers": {
    "<serverKey>": {
      "command": "<command>",
      "args": ["<arg>"],
      "env": {
        "<KEY>": "<value>"
      }
    }
  }
}
```

mcp-inator reads/writes only the `mcpServers` key. Other keys in the file are preserved (round-tripped as opaque JSON).

### TOML agent (Codex CLI)

Agent config file shape:
```toml
[mcp_servers.<serverKey>]
command = "<command>"
args = ["<arg>"]

[mcp_servers.<serverKey>.env]
KEY = "value"
```

mcp-inator reads/writes only the `mcp_servers` section. Other TOML keys are preserved.
