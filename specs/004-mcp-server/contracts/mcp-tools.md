# MCP Tool Contracts

Transport: JSON-RPC 2.0 over stdin/stdout (one message per line, newline-delimited).

All messages include `"jsonrpc": "2.0"`. Requests include `"id"` (int or string).
Notifications (e.g., `initialized`) have no `"id"`.

---

## Initialization Handshake

### Client → Server: `initialize`

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": { "name": "claude-code", "version": "1.0.0" }
  }
}
```

### Server → Client: initialize result

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "mcp-inator", "version": "0.1.0" }
  }
}
```

### Client → Server: `notifications/initialized` (notification, no id)

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

Server ignores this notification (no response sent).

---

## `tools/list`

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

### Response

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "list_servers",
        "description": "List all MCP server configurations in the mcp-inator library.",
        "inputSchema": {
          "type": "object",
          "properties": {},
          "required": []
        }
      },
      {
        "name": "add_server",
        "description": "Add a new stdio MCP server configuration to the library.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "name":    { "type": "string", "description": "Display name (e.g. 'Playwright')" },
            "command": { "type": "string", "description": "Executable path or name (e.g. 'npx')" },
            "args":    { "type": "array", "items": { "type": "string" }, "description": "CLI arguments" },
            "env":     { "type": "object", "additionalProperties": { "type": "string" }, "description": "Environment variables" }
          },
          "required": ["name", "command"]
        }
      },
      {
        "name": "remove_server",
        "description": "Remove a server configuration from the library. Cannot remove the built-in 'mcp-inator' entry.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "server_name": { "type": "string", "description": "serverKey of the server to remove" }
          },
          "required": ["server_name"]
        }
      },
      {
        "name": "enable_server",
        "description": "Enable a server for a specific agent by writing it to the agent's config file.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "server_name": { "type": "string", "description": "serverKey of the server" },
            "agent":       { "type": "string", "description": "Agent identifier: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop" }
          },
          "required": ["server_name", "agent"]
        }
      },
      {
        "name": "disable_server",
        "description": "Disable a server for a specific agent by removing it from the agent's config file.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "server_name": { "type": "string", "description": "serverKey of the server" },
            "agent":       { "type": "string", "description": "Agent identifier: claude_code, claude_desktop, gemini_cli, codex_cli, gemini_desktop" }
          },
          "required": ["server_name", "agent"]
        }
      },
      {
        "name": "list_agents",
        "description": "List all discovered AI agents and their current availability.",
        "inputSchema": {
          "type": "object",
          "properties": {},
          "required": []
        }
      }
    ]
  }
}
```

---

## `tools/call` — `list_servers`

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": { "name": "list_servers", "arguments": {} }
}
```

### Response (success)

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "[{\"serverKey\":\"playwright\",\"displayName\":\"Playwright\",\"command\":\"npx\",\"args\":[\"-y\",\"@playwright/mcp@latest\"],\"transportType\":\"stdio\"},{\"serverKey\":\"mcp-inator\",\"displayName\":\"mcp-inator\",\"command\":\"/Applications/mcp-inator.app/Contents/MacOS/mcp-inator\",\"args\":[\"--mcp-server\"],\"transportType\":\"stdio\"}]"
      }
    ]
  }
}
```

---

## `tools/call` — `add_server`

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "add_server",
    "arguments": {
      "name": "Playwright",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

### Response (success)

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [{ "type": "text", "text": "Added server 'playwright'" }]
  }
}
```

### Response (duplicate error)

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [{ "type": "text", "text": "Error: server 'playwright' already exists" }],
    "isError": true
  }
}
```

---

## `tools/call` — `remove_server`

### Response (protected entry)

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "content": [{ "type": "text", "text": "Error: 'mcp-inator' is a built-in entry and cannot be removed" }],
    "isError": true
  }
}
```

---

## `tools/call` — `enable_server`

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "enable_server",
    "arguments": {
      "server_name": "playwright",
      "agent": "claude_code"
    }
  }
}
```

### Response (success)

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "content": [{ "type": "text", "text": "Enabled 'playwright' for claude_code" }]
  }
}
```

### Response (agent not found)

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "content": [{ "type": "text", "text": "Error: agent 'claude_code' not found — run a discovery scan first" }],
    "isError": true
  }
}
```

---

## `tools/call` — `list_agents`

### Response (success)

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "[{\"agentType\":\"claude_code\",\"displayName\":\"Claude Code\",\"configPath\":\"/Users/ray/.claude/claude_desktop_config.json\",\"isAvailable\":true}]"
      }
    ]
  }
}
```

---

## Error Responses (method-level)

### Unknown method

```json
{
  "jsonrpc": "2.0",
  "id": 99,
  "error": { "code": -32601, "message": "Method not found: 'foo'" }
}
```

### Parse error (malformed JSON)

```json
{
  "jsonrpc": "2.0",
  "id": null,
  "error": { "code": -32700, "message": "Parse error" }
}
```

### Invalid params (missing required field)

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "error": { "code": -32602, "message": "Invalid params: 'command' is required" }
}
```

---

## Tool Error Convention

MCP distinguishes **protocol errors** (HTTP-equivalent, returned in `error` field) from
**tool errors** (the tool ran but produced a failure, returned in `result` with `isError: true`).

- Use `error` field only for: parse error, invalid request, method not found, missing required params.
- Use `result.isError = true` for: business logic failures (server not found, agent not found, duplicate, protected entry).

---

## `ping`

```json
{ "jsonrpc": "2.0", "id": 10, "method": "ping" }
```

Response:

```json
{ "jsonrpc": "2.0", "id": 10, "result": {} }
```
