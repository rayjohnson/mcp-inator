# Quickstart: MCP Server Integration Scenarios

## Prerequisites

- mcp-inator built and installed
- A terminal with `echo` and the mcp-inator binary in PATH (or referenced by full path)

---

## Scenario 1: List existing servers (cold DB)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_servers","arguments":{}}}' \
  | /Applications/mcp-inator.app/Contents/MacOS/mcp-inator --mcp-server
```

**Expected**: Two JSON responses on stdout — one for `initialize` (result with capabilities), one for `tools/list` (six tools), one for `tools/call` (JSON array of servers including the mcp-inator self-entry).

---

## Scenario 2: Add and enable a server for Claude Code

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add_server","arguments":{"name":"Playwright","command":"npx","args":["-y","@playwright/mcp@latest"]}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"enable_server","arguments":{"server_name":"playwright","agent":"claude_code"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_servers","arguments":{}}}' \
  | /Applications/mcp-inator.app/Contents/MacOS/mcp-inator --mcp-server
```

**Expected**: 
- id=2 result: `"Added server 'playwright'"`
- id=3 result: `"Enabled 'playwright' for claude_code"`
- id=4 result: JSON array includes playwright entry

**Side effect**: `~/.claude/claude_desktop_config.json` now includes a `playwright` entry.

---

## Scenario 3: Enable mcp-inator for itself (self-registration)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"enable_server","arguments":{"server_name":"mcp-inator","agent":"claude_code"}}}' \
  | /Applications/mcp-inator.app/Contents/MacOS/mcp-inator --mcp-server
```

**Expected**: id=2 result success; claude_desktop_config.json now includes:
```json
"mcp-inator": {
  "command": "/Applications/mcp-inator.app/Contents/MacOS/mcp-inator",
  "args": ["--mcp-server"]
}
```

---

## Scenario 4: Attempt to remove built-in entry (should fail)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"remove_server","arguments":{"server_name":"mcp-inator"}}}' \
  | /Applications/mcp-inator.app/Contents/MacOS/mcp-inator --mcp-server
```

**Expected**: id=2 result with `"isError": true` and message about built-in entry.

---

## Scenario 5: Unknown method (error path)

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"foo","params":{}}' \
  | /Applications/mcp-inator.app/Contents/MacOS/mcp-inator --mcp-server
```

**Expected**: Response with `"error": {"code": -32601, "message": "Method not found: 'foo'"}`.

---

## Scenario 6: Verify UI shows lock badge on mcp-inator entry

1. Launch mcp-inator.app normally.
2. Open the Servers tab.
3. Locate the "mcp-inator" entry — it should have a lock badge.
4. Confirm that no edit or delete controls are visible for this entry.

---

## Adding to Claude Code's MCP config (manual equivalent)

After `enable_server` succeeds, the entry in `~/.claude/claude_desktop_config.json` should be:

```json
{
  "mcpServers": {
    "mcp-inator": {
      "command": "/path/to/mcp-inator.app/Contents/MacOS/mcp-inator",
      "args": ["--mcp-server"]
    }
  }
}
```

Claude Code will then be able to call mcp-inator's tools in subsequent sessions.
