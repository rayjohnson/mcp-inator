# Implementation Plan: Cursor Agent Support

**Branch**: `012-cursor-agent-support` | **Date**: 2026-05-31 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-cursor-agent-support/spec.md`

## Summary

Add `CursorAdapter` so mcp-inator discovers, reads, writes, and imports MCP server
configs from `~/.cursor/mcp.json`. Cursor IDE and Cursor CLI share a single config
file with the same JSON format as Claude Desktop (`{"mcpServers": {...}}`), so the
adapter is a near-identical copy of `ClaudeDesktopAdapter` with a different path and
`AgentType`. No database migration is required — `AgentType` stores raw strings.

## Technical Context

**Language/Version**: Swift 5.9, macOS 14+ deployment target

**Primary Dependencies**: SwiftUI, GRDB (SQLite persistence), `JSONAdapterHelper`
(shared read/write/drift-detection logic already in the codebase)

**Storage**: GRDB SQLite for `AgentRecord`; `~/.cursor/mcp.json` for Cursor's config file

**Testing**: XCTest — unit tests for `validateServerKey`, integration tests for
read/write/remove/isInstalled paths (mirrors `ClaudeDesktopAdapterTests`)

**Target Platform**: macOS 14+ (menu bar app, two-mode: popover + dock window)

**Project Type**: macOS desktop app (SwiftUI + AppKit hybrid)

**Performance Goals**: Same as other adapters — file I/O is synchronous and negligible

**Constraints**: Must not break any existing adapter; `AgentType` backward compatibility
required (raw-string storage; unknown values fall back to `.claudeCode`)

**Scale/Scope**: ~4 small files added/modified; no schema migration; ~1 new test file

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | PASS | Pure SwiftUI/AppKit; no web tech; same patterns as existing adapters |
| II. Single Source of Truth | PASS | `CursorAdapter` reads/writes `~/.cursor/mcp.json` as a derived output |
| III. Non-Destructive Configuration | PASS | Drift detection inherited from `JSONAdapterHelper`; disable removes entry only |
| IV. Config Portability | PASS | Existing library configs apply to Cursor via single toggle, same as all adapters |
| V. Simplicity & Discoverability | PASS | One new case in enum + one new adapter struct; no novel abstractions |

No complexity violations. Complexity Tracking table not required.

## Project Structure

### Documentation (this feature)

```text
specs/012-cursor-agent-support/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code Changes

```text
mcp-inator/
├── Adapters/
│   └── CursorAdapter.swift          # NEW — mirrors ClaudeDesktopAdapter
├── Models/
│   └── AgentRecord.swift            # MODIFY — add .cursor case to AgentType enum
└── UI/
    └── AgentIcon.swift              # MODIFY — add .cursor case returning LetterBadge

mcp-inator/App/
└── mcp_inatorApp.swift              # MODIFY — add CursorAdapter() to adapters array

mcp-inator/UI/
└── MenuBarView.swift                # MODIFY — add CursorAdapter() to allAdapters

mcp-inatorTests/
└── Integration/
    └── CursorAdapterTests.swift     # NEW — mirrors ClaudeDesktopAdapterTests
```

**Structure Decision**: Single-project macOS app. All changes are additive to existing
adapter/model/UI files. Pattern is identical to adding `CodexCLIAdapter` or `GeminiCLIAdapter`.
