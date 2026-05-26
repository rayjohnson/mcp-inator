# Contract: GeminiDesktopAdapter

**Conforms to**: `AgentAdapter` protocol (`mcp-inator/Adapters/AgentAdapter.swift`)

## Identity

| Property | Value |
|----------|-------|
| `agentType` | `.geminiDesktop` |
| `displayName` | `"Gemini Desktop"` |
| `isAppManaged` | `true` |

## Detection

`isInstalled()` returns `true` if either:
1. `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS")` returns non-nil, OR
2. `FileManager.default.fileExists(atPath: "/Applications/Gemini.app")` returns `true`

Returns `false` (no throw) if neither condition holds.

## Path Resolution

```
defaultConfigPath() → ~/Library/Application Support/Google/Gemini/mcp_servers.json
```

This file is not expected to exist. The path is a sentinel — present to satisfy the protocol but not used by the UI (the "in-app managed" banner is shown instead of file-based controls). The directory is NOT created on first write (no write operations occur).

## Read / Write Behaviour (No-ops)

Gemini Desktop stores MCP config in its internal SQLite database. mcp-inator cannot read or write it.

| Method | Behaviour |
|--------|-----------|
| `readConfigs(from:)` | Returns `[:]` immediately, no file access |
| `writeConfigs(_:to:expectedExisting:)` | Returns `.success` immediately, no file write |
| `removeConfig(key:from:expectedValue:)` | Returns `.success` immediately, no file write |
| `validateServerKey(_:)` | Returns `.valid` (no keys are ever written) |

## Protocol Extension: `isAppManaged`

The `AgentAdapter` protocol gains a default-`false` `isAppManaged: Bool` property. Only `GeminiDesktopAdapter` returns `true`. All existing adapters are unaffected.

`AgentListView` checks `adapter.isAppManaged` to show the "in-app managed" banner instead of the normal toggle list or unavailable banner.

## UI Behaviour in AgentListView

When `adapter.isAppManaged == true`:
- Banner text: `"Gemini Desktop manages MCP servers internally. Add servers directly in the Gemini app settings."`
- No MCP server toggle list
- No "Change Path" button
- No "Import" toolbar item
- Agent icon and config path subtitle are still shown in the header

## Background

Binary analysis of `/Applications/Gemini.app` confirms:
- MCP is supported (`McpServer`, `mcpServersArray` present in binary)
- Transport is HTTP/Streamable-HTTP only (`GAIGLTool_McpServer_StreamableHttpTransport`); no stdio
- Config is stored in `~/Library/Application Support/com.google.GeminiMacOS/Data/*.store` (SQLite)
- No external JSON config file exists

If Google publishes a file-based MCP config path in a future release, only this adapter needs updating — the rest of the app is unchanged.
