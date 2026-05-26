# Data Model: Gemini Desktop Support + Agent Visibility Controls

## Changes to Existing Entities

### `AgentAdapter` protocol (in `Adapters/AgentAdapter.swift`)

New optional property with default implementation:

```swift
var isAppManaged: Bool { get }
// Default implementation (extension):
var isAppManaged: Bool { false }
```

All existing adapters inherit `false` with no changes. `GeminiDesktopAdapter` overrides to return `true`.

### `AgentType` (enum in `Models/AgentRecord.swift`)

New case:

| Case | Raw Value | displayName | defaultConfigPath |
|------|-----------|-------------|-------------------|
| `.geminiDesktop` | `"gemini_desktop"` | `"Gemini Desktop"` | `~/Library/Application Support/Google/Gemini/mcp_servers.json` (sentinel; file will not exist) |

### `AgentRecord` (struct in `Models/AgentRecord.swift`)

New field:

| Field | Type | Default | SQLite column |
|-------|------|---------|---------------|
| `isVisible` | `Bool` | `true` | `isVisible INTEGER NOT NULL DEFAULT 1` |

`encode(to:)` adds: `container["isVisible"] = isVisible ? 1 : 0`  
`init(row:)` adds: `isVisible = (row["isVisible"] as Int) != 0`  
`init(agentType:configPath:)` defaults to `isVisible = true`

---

## New Entity: `GeminiDesktopAdapter`

New file: `mcp-inator/Adapters/GeminiDesktopAdapter.swift`

```
struct GeminiDesktopAdapter: AgentAdapter {
    agentType:    AgentType = .geminiDesktop
    displayName:  String    = "Gemini Desktop"
    isAppManaged: Bool      = true

    defaultConfigPath() → ~/Library/Application Support/Google/Gemini/mcp_servers.json
      (sentinel path; file is not expected to exist)

    isInstalled() → Bool
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") != nil
      OR FileManager.default.fileExists(atPath: "/Applications/Gemini.app")

    readConfigs(from:)   → returns [:]  (no-op; app manages internally)
    writeConfigs(...)    → returns .success  (no-op)
    removeConfig(...)    → returns .success  (no-op)
    validateServerKey(_:) → .valid  (no-op; no keys to write)
}
```

---

## New DB Migration: `Migration004`

New file: `mcp-inator/Store/Migrations/Migration004.swift`

```sql
ALTER TABLE agents
    ADD COLUMN isVisible INTEGER NOT NULL DEFAULT 1;
```

Migration key: `"004_agent_visibility"`

All existing rows default to visible. No data migration required.

---

## New Store API

### `ConfigStore`

```swift
// Computed filter — not @Published; re-derives from agents on access
var visibleAgents: [AgentRecord] { agents.filter(\.isVisible) }

// Persist visibility change
func setAgentVisibility(agentId: Int64, visible: Bool) throws
    // Updates isVisible in agents table
    // Does NOT touch config_agent_assignments or mcp_server_configs
```

`fetchStatusMatrix()` — updated to only include agents where `isVisible = 1` in the join, so hidden agents produce no badge columns.

`PropagationView` agent list — updated to use `store.visibleAgents` instead of `store.agents`.

---

## State Transitions

```
isVisible state machine:

    true (default) ──→ false (hidden)
                          │
                          └──→ true (restored)
```

Transitioning to `false` does NOT affect:
- `AgentRecord.isAvailable`
- `ConfigAgentAssignment` records
- `MCPServerConfig` records

Transitioning back to `true` restores full badge and assignment state.

---

## `AgentListView` Rendering Logic (updated)

```
if adapter.isAppManaged:
    → show "in-app managed" banner
      (no toggle list, no Change Path button)
else if !agent.isAvailable:
    → show existing "Config file not accessible" + Change Path banner
else:
    → show existing MCP server toggle list
```
