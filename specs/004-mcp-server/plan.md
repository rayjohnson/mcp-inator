# Implementation Plan: Built-in MCP Server

**Branch**: `004-mcp-server` | **Date**: 2026-05-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-mcp-server/spec.md`

## Summary

Add an MCP-over-stdio server to mcp-inator so that AI agents (Claude Code, Gemini CLI, etc.) can
programmatically list, add, remove, enable, and disable MCP server configurations. The server is
invoked by launching the app binary with `--mcp-server`; it performs a JSON-RPC 2.0 handshake on
stdin/stdout and then handles tool calls directly against the GRDB database — no running app
instance required. A pinned, read-only self-entry for mcp-inator is seeded into the library so
agents can add mcp-inator to themselves.

## Technical Context

**Language/Version**: Swift 6.0, macOS 13.0+

**Primary Dependencies**: GRDB 6.x (existing), `modelcontextprotocol/swift-sdk` ≥ 0.11.0 (new)

**Storage**: SQLite via GRDB — same database used by the main app

**Testing**: XCTest; integration tests use a real in-process `Process` piping stdin/stdout

**Target Platform**: macOS 13.0+

**Project Type**: macOS menu bar app (desktop-app); MCP server runs as a separate execution mode
of the same binary, not a separate target

**Performance Goals**: `tools/list` round-trip < 500 ms cold; `tools/call` < 200 ms

**Constraints**: stdio transport only; no HTTP/SSE; no auth; no XPC; direct DB access

**Scale/Scope**: Single-user local tool; no concurrency beyond two simultaneous processes writing
to the same SQLite DB (handled by GRDB WAL mode)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | ✅ PASS | Main app remains SwiftUI menu bar. MCP server is a CLI mode of the same binary — not a new UI layer. |
| II. Single Source of Truth | ✅ PASS | MCP server reads/writes the same GRDB database as the app. No duplicate config storage. |
| III. Non-Destructive Configuration | ✅ PASS | `enable_server`/`disable_server` use existing adapter layer — same semantics as the UI toggle. |
| IV. Config Portability | ✅ PASS | Tools expose cross-agent operations; underlying adapters handle format differences. |
| V. Simplicity & Discoverability | ✅ PASS | Six focused tools; self-entry in library makes mcp-inator discoverable by agents. |

**No violations.** No Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/004-mcp-server/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── mcp-tools.md     # MCP tool schemas (JSON-RPC 2.0 contracts)
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
mcp-inator/
├── App/
│   ├── mcp_inatorApp.swift          # Remove @main; keep as App struct
│   └── main.swift                   # NEW: replaces @main; checks --mcp-server, routes accordingly
├── MCP/                              # NEW: MCP server subsystem
│   ├── MCPServer.swift              # Creates MCP.Server, seeds self-entry, registers handlers, runs StdioTransport
│   └── MCPTools.swift               # Tool implementations: list_servers, add_server, etc.
├── Models/
│   └── (existing models unchanged)
└── Store/
    └── (existing store unchanged)

mcp-inatorTests/
└── Integration/
    └── MCPServerTests.swift         # End-to-end tests via in-process pipe (Process + stdin/stdout)
```

**Structure Decision**: Single-target approach. `@main` is removed from `mcp_inatorApp` and a new
`main.swift` (in `App/` alongside other entry-point code) checks `CommandLine.arguments` before the
SwiftUI lifecycle starts. `MCPServer.swift` uses the official `MCP` SDK (`MCP.Server` +
`StdioTransport`) — no hand-rolled JSON-RPC types needed. `MCPTools.swift` contains the business
logic for each tool. Tests go in `Integration/` (not `Unit/`) because they spawn a real process.
No new Xcode target needed; `project.yml` gains the `swift-sdk` package dependency.

**App-managed agents**: `enable_server` and `disable_server` MUST return a tool error (not silent
success) when called with an app-managed agent (e.g., `gemini_desktop`). Error message:
`"'gemini_desktop' is app-managed — MCP configuration cannot be written by mcp-inator"`.

**Self-entry seeding**: `MCPServer.run()` MUST call a `seedSelfEntry(store:)` function before
starting the SDK's run loop. This ensures the mcp-inator library entry exists when running headless
(i.e., when the SwiftUI app is not launched). The same function is called on app launch from
`mcp_inatorApp`.

## Complexity Tracking

> No constitution violations to track.
