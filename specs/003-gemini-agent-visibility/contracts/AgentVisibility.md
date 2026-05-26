# Contract: Agent Visibility

## Overview

`isVisible` is a per-agent Boolean preference stored in the `agents` table. It controls whether an agent appears in day-to-day UI surfaces. Hiding an agent is non-destructive: all configs and assignments are preserved.

## Visibility Surfaces

| Surface | Visible agents only | All agents |
|---------|--------------------:|----------:|
| Agents tab list | ✓ | — |
| Servers tab agent badges | ✓ | — |
| "Manage Agents" view | — | ✓ |
| DiscoveryView (new agent onboarding) | — | ✓ |

## ConfigStore API

### `func setAgentVisibility(agentId: Int64, visible: Bool) throws`

- Updates `isVisible` in the `agents` table for the given `agentId`.
- Does not touch any `config_agent_assignments` or `mcp_server_configs` rows.
- Callers: `ManageAgentsView` toggle action.

### `func fetchVisibleAgents() throws -> [AgentRecord]`

- Returns agents where `isVisible = 1`, ordered by `discoveredAt ASC`.
- Used by: Agents tab list, `fetchStatusMatrix`.

### `func fetchAllAgents() throws -> [AgentRecord]`

- Returns all agents regardless of `isVisible`, ordered by `discoveredAt ASC`.
- Used by: `ManageAgentsView`.

### `func fetchStatusMatrix() throws -> [StatusRow]`

- Existing method; updated to inner-join only agents where `isVisible = 1`.
- Badge columns in `ConfigLibraryView` only appear for visible agents.

## ManageAgentsView Contract

A pushed `NavigationStack` view (not a sheet, per app navigation pattern):

**Title**: "Manage Agents"

**Content**: `List` of all agents (visible + hidden) from `fetchAllAgents()`.

Each row:
- `AgentIcon` (24×24)
- `displayName`
- Availability indicator (green checkmark if `isAvailable`)
- `Toggle` bound to `isVisible`, labeled "Show" / "Hidden"

Toggle action calls `store.setAgentVisibility(agentId: agent.id!, visible: newValue)`.

**Access point**: Agents tab toolbar button (gear icon or `"person.2.badge.gearshape"` system image).

## Migration Contract

`Migration004` key: `"004_agent_visibility"`

```sql
ALTER TABLE agents
    ADD COLUMN isVisible INTEGER NOT NULL DEFAULT 1;
```

All existing agents default to visible (`1`). No data migration required.
