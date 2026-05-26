# Data Model: Built-in MCP Server

## Existing Entities (unchanged)

### MCPServerConfig
Stored in `mcp_server_configs` table via GRDB.

| Field | Type | Notes |
|-------|------|-------|
| id | Int64? | DB row ID, nil before insert |
| uuid | UUID | Stable identifier used by MCP tools |
| displayName | String | Human label ("Playwright") |
| serverKey | String | Slug used in agent config files ("playwright") |
| transportType | stdio \| http \| sse | Only stdio entries are writable via MCP tools in this feature |
| command | String | Executable path (stdio only) |
| args | [String] | CLI arguments (stdio only) |
| url | String | HTTP/SSE URL (http/sse only) |
| envVars | [EnvVar] | Environment variables or HTTP headers |
| notes | String | Free-form notes |
| createdAt | Date | Insert timestamp |
| updatedAt | Date | Last-update timestamp |

**Self-entry constraint**: The entry with `serverKey == "mcp-inator"` is seeded on every app launch. It is read-only in the UI (edit/delete controls are hidden) and in the MCP tools (`remove_server` returns an error if called with `"mcp-inator"`).

### AgentRecord
Stored in `agents` table via GRDB.

| Field | Type | Notes |
|-------|------|-------|
| id | Int64? | DB row ID |
| agentType | AgentType | .claudeCode, .claudeDesktop, .geminiCLI, .codexCLI, .geminiDesktop |
| displayName | String | "Claude Code", "Claude Desktop", etc. |
| configPath | String | Absolute path to agent's config file |
| isAvailable | Bool | Detected at last scan |
| isVisible | Bool | User visibility toggle |

**MCP exposure**: `list_agents` returns all AgentRecords with their `agentType.rawValue` as the identifier for `enable_server`/`disable_server` calls.

## New Entities

### MCPRequest (Codable, in-memory only)
Represents a JSON-RPC 2.0 request received on stdin.

| Field | Type | Notes |
|-------|------|-------|
| jsonrpc | String | Always "2.0" |
| id | JSONRPCId? | Int or String; nil for notifications |
| method | String | "initialize", "notifications/initialized", "tools/list", "tools/call", "ping" |
| params | [String: JSONValue]? | Method-specific parameters |

### MCPResponse (Codable, in-memory only)
Represents a JSON-RPC 2.0 response written to stdout.

| Field | Type | Notes |
|-------|------|-------|
| jsonrpc | String | Always "2.0" |
| id | JSONRPCId | Mirrors the request id |
| result | JSONValue? | Present on success |
| error | MCPError? | Present on failure |

### MCPError (Codable, in-memory only)

| Field | Type | Notes |
|-------|------|-------|
| code | Int | -32700 parse, -32600 invalid request, -32601 method not found, -32602 invalid params, -32603 internal error |
| message | String | Human-readable error message |

### JSONRPCId (Codable, in-memory only)
An enum: `.int(Int)` \| `.string(String)` — handles both integer and string request IDs from diverse MCP clients.

### JSONValue (Codable, in-memory only)
A recursive enum representing any JSON value: `.null`, `.bool(Bool)`, `.int(Int)`, `.double(Double)`, `.string(String)`, `.array([JSONValue])`, `.object([String: JSONValue])`. Used for flexible params and result encoding.

## State Transitions

```
add_server ──→ MCPServerConfig in DB (disabled for all agents)
                │
     enable_server(name, agent)
                │
                ▼
        Config written to agent's file
                │
     disable_server(name, agent)
                │
                ▼
        Config removed from agent's file (record remains in DB)
                │
     remove_server(name)   [not allowed for "mcp-inator"]
                │
                ▼
        Record deleted from DB
```

## Seeding: mcp-inator self-entry

On every app launch (and at the start of every `--mcp-server` session), the following is upserted
into `mcp_server_configs` by `serverKey`:

```
displayName: "mcp-inator"
serverKey:   "mcp-inator"
command:     <Bundle.main.executableURL.path>  — resolved at write time, not stored
args:        ["--mcp-server"]
envVars:     []
```

The command is **not** stored permanently as the bundle path; instead it is computed at the moment
`enable_server` is called for the mcp-inator entry, so it stays correct after app relocation.
The DB record stores an empty placeholder command (`""`) or the current bundle path — either way,
at `enable_server` time the adapter receives the current `Bundle.main.executableURL.path`.
