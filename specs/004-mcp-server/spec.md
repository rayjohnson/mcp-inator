# Feature Specification: Built-in MCP Server

**Feature Branch**: `004-mcp-server`

**Created**: 2026-05-26

**Status**: Draft

**Input**: GitHub Issue #2 — "Add an mcp server to allow AI agents to control mcp-inator"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI agents discover and manage MCP servers via stdio (Priority: P1)

An AI agent (e.g., Claude Code, Gemini CLI) running inside a terminal can invoke the mcp-inator binary
as an MCP tool server over stdio. Through the MCP protocol the agent can list all configured MCP
servers, add a new server, enable/disable a server for a given agent, and remove a server — all
without opening any GUI.

**Why this priority**: This is the core value: allowing automated workflows to stay in sync with
mcp-inator's config library. Everything else is polish.

**Independent Test**: Point any MCP-compatible client at `mcp-inator --mcp-server`, send
`tools/list`, and confirm the six tools appear; call `add_server` with valid args and confirm the
server appears in `list_servers` output.

**Acceptance Scenarios**:

1. **Given** the mcp-inator app is installed and running, **When** a client sends `initialize` then
   `tools/list` over stdin/stdout, **Then** the server responds with the MCP handshake and a list
   containing at least: `list_servers`, `add_server`, `remove_server`, `enable_server`,
   `disable_server`, `list_agents`.

2. **Given** no server named "playwright" exists, **When** the client calls `add_server` with
   `{"name":"playwright","command":"npx","args":["-y","@playwright/mcp@latest"]}`, **Then** the
   server returns success and `list_servers` now includes "playwright".

3. **Given** server "playwright" exists, **When** the client calls `enable_server` with
   `{"server_name":"playwright","agent":"claude-code"}`, **Then** the server writes the config to
   Claude Code's `claude_desktop_config.json` and returns success.

4. **Given** server "playwright" is enabled for claude-code, **When** the client calls
   `disable_server` with `{"server_name":"playwright","agent":"claude-code"}`, **Then** the server
   removes the entry from Claude Code's config and returns success.

5. **Given** server "playwright" exists, **When** the client calls `remove_server` with
   `{"server_name":"playwright"}`, **Then** the server removes it from the library and returns
   success.

6. **Given** the app is not running, **When** a client connects and calls any tool, **Then** the
   server still works (IPC to the running app is optional; direct DB access is acceptable).

---

### User Story 2 - mcp-inator appears as a pinned, non-editable entry in the server library (Priority: P2)

After the built-in MCP server is implemented, mcp-inator automatically adds itself to the server
library as a special read-only entry. Users can see it in the Servers tab with a lock badge, can
enable/disable it for agents, but cannot edit or delete it.

**Why this priority**: Discoverability — an agent that adds mcp-inator to itself can then
instruct future sessions to use it, creating a self-perpetuating configuration.

**Independent Test**: Launch the app fresh; open the Servers tab and confirm an entry named
"mcp-inator" is present with a lock icon and that the edit/delete buttons are absent.

**Acceptance Scenarios**:

1. **Given** a fresh app install, **When** the Servers tab is opened, **Then** an entry "mcp-inator"
   appears with a lock badge.

2. **Given** the mcp-inator entry is selected, **When** the user tries to edit or delete it, **Then**
   the edit and delete controls are hidden or disabled.

3. **Given** the mcp-inator entry exists, **When** the user toggles it on for claude-code, **Then**
   the binary path written to claude_desktop_config.json points to the actual installed app binary.

---

### User Story 3 - Bundle-relative binary path survives app updates (Priority: P3)

When the mcp-inator server entry is written to an agent's config, the command path is derived from
the currently running app bundle (`Bundle.main.executableURL`) so it stays correct after the user
moves or updates the app.

**Why this priority**: A hard-coded path would break after a Homebrew or manual update. This ensures
the path is always correct at the moment of writing.

**Independent Test**: Move the .app to a different path; re-enable the mcp-inator server for
claude-code; confirm the written path matches the new location.

**Acceptance Scenarios**:

1. **Given** the app bundle is at `/Applications/mcp-inator.app`, **When** `enable_server` is called
   for the mcp-inator entry, **Then** the written command is
   `/Applications/mcp-inator.app/Contents/MacOS/mcp-inator`.

2. **Given** the app bundle is moved to `~/Applications/mcp-inator.app`, **When** `enable_server`
   is called, **Then** the written command reflects the new path, not the old one.

---

### Edge Cases

- What happens when two mcp-inator processes are running simultaneously and both receive tool calls?
  (Answer: each process opens the DB in WAL mode; GRDB handles concurrent access.)
- What if the client sends a `tools/call` for an unknown tool name? Return MCP error code -32601.
- What if `add_server` is called with a `name` that already exists? Return an error with message
  "server already exists".
- What if the DB is locked when a tool call arrives? Surface the SQLite error as an MCP tool error.
- What if the app has never been launched and the DB does not exist? The `--mcp-server` mode must
  initialize the DB itself.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose an MCP-over-stdio server when invoked with `--mcp-server`.
- **FR-002**: Server MUST implement the MCP `initialize` / `initialized` handshake.
- **FR-003**: Server MUST advertise tools: `list_servers`, `add_server`, `remove_server`,
  `enable_server`, `disable_server`, `list_agents`.
- **FR-004**: `list_servers` MUST return all MCPServerConfig entries from the library.
- **FR-005**: `add_server` MUST insert a new MCPServerConfig into the library; reject duplicates.
- **FR-006**: `remove_server` MUST delete the named config; reject if not found.
- **FR-007**: `enable_server` MUST write the config to the named agent's file using the existing
  adapter; reject if agent or server not found.
- **FR-008**: `disable_server` MUST remove the config from the named agent's file.
- **FR-009**: `list_agents` MUST return all discovered AgentRecords with their availability status.
- **FR-010**: Server MUST respond to unknown tool names with MCP error -32601.
- **FR-011**: The mcp-inator entry MUST be seeded into the library on first launch and on every
  subsequent launch if missing.
- **FR-012**: The mcp-inator entry MUST be read-only (edit/delete disabled in UI).
- **FR-013**: The binary path in the mcp-inator entry MUST be resolved from `Bundle.main.executableURL`
  at write time, not stored as a literal.

### Key Entities

- **MCPServerConfig** (existing): displayName, serverKey, command, args, env — used as the library
  record for each server including the mcp-inator self-entry.
- **AgentRecord** (existing): agentType, displayName, configPath, isAvailable — returned by
  `list_agents`.
- **MCPRequest / MCPResponse** (new): Codable structs representing JSON-RPC 2.0 messages on stdin/
  stdout for the MCP server loop.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `tools/list` round-trip completes in under 500 ms on a cold DB.
- **SC-002**: All six tools pass end-to-end tests via a real `Process`/pipe (no mocks).
- **SC-003**: The mcp-inator self-entry is present in the library on every app launch.
- **SC-004**: CI passes (build + unit tests) on every push.

## Assumptions

- Transport is stdio only; HTTP/SSE is out of scope for this feature.
- Authentication is out of scope; the tool assumes local-only access.
- The built-in server is a Swift `CommandLineTool` target added to the Xcode project, sharing the
  same codebase as the main app target via a shared Swift Package or direct file references.
- The `--mcp-server` flag is passed via the app's launch argument handling (checked in `main.swift`
  or the App entry point before the SwiftUI lifecycle starts).
- The server communicates with the database directly (no XPC to the running app instance).
- Remote access and multi-user scenarios are out of scope.
