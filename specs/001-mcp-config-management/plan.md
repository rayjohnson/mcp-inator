# Implementation Plan: MCP Server Configuration Management

**Branch**: `001-mcp-config-management` | **Date**: 2026-05-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-mcp-config-management/spec.md`

## Summary

Build the core of mcp-inator: a native macOS menubar app that acts as a single source of
truth for MCP server configurations across AI tools. Users add configs once; the app applies
them to any supported agent (Claude Code CLI, Claude Desktop, Gemini CLI, Codex CLI) with
per-agent adapters handling JSON format differences. Key behaviors: enable/disable per agent
(non-destructive), first-run agent discovery with per-entry import, edit propagation with
pre-flight diff checking, atomic file writes, and graceful empty-state recovery.

## Technical Context

**Language/Version**: Swift 5.9+ / SwiftUI; minimum deployment target macOS 13.0 (Ventura)

**Primary Dependencies**:
- SwiftUI + AppKit (NSStatusItem) — menubar popover UI
- Sparkle 2.x — auto-update (constitution-mandated)
- GRDB 6.x — SQLite-backed config store with migration support
- Foundation (FileManager, JSONSerialization) — atomic file I/O, agent config reading/writing

**Storage**: Local SQLite database via GRDB for the config library (MCPServerConfig records,
Agent records, ConfigAgentAssignment records). Agent config files (JSON) are derived outputs
written by adapters; they are not mcp-inator's primary store.

**Testing**: XCTest for unit and integration tests; integration tests use fixture JSON files
per adapter to verify read/write correctness without touching real agent installs.

**Target Platform**: macOS 13.0+ (Ventura) — single-user personal tool, no server component

**Project Type**: macOS menubar app (NSStatusItem + SwiftUI popover)

**Performance Goals**:
- Enable/disable a single config: <2s (SC-002)
- First-run agent scan: <5s (SC-010)
- UI interactions (open popover, navigate views): <100ms perceived

**Constraints**:
- **macOS sandbox policy**: See research.md R-002. **Unsandboxed** — distributed via
  GitHub Releases and Homebrew cask (not App Store). Developer ID signing + Hardened
  Runtime + notarization + stapling required. `~/Library/Application Support/` is not
  TCC-protected; no Security-Scoped Bookmarks or NSOpenPanel required for config writes.
- All agent config writes MUST be atomic (temp file + rename, FR-027)
- No network connectivity required except Sparkle update checks
- App MUST be code-signed and notarized (constitution)

**Scale/Scope**: Single-user; expected <100 MCP server configs; 4 supported agents at launch;
adapter list grows over time without changing core storage.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| I. Native macOS Experience | SwiftUI menubar app, HIG-compliant, Sparkle auto-update | ✅ PASS | NSStatusItem + SwiftUI popover; Sparkle in dependencies |
| II. Single Source of Truth | GRDB store is canonical; agent files are derived | ✅ PASS | All adapters write from canonical model; store never reads back from agents except import/pre-flight |
| III. Non-Destructive Configuration | Disable removes from file, not from store; delete requires confirmation; pre-flight diff before overwrite | ✅ PASS | FR-006, FR-004, FR-023, FR-027 all implemented |
| IV. Config Portability | Agent-agnostic canonical model; AgentAdapter protocol; bulk apply | ✅ PASS | FR-008, FR-015, FR-010 extensible adapter architecture |
| V. Simplicity & Discoverability | Actionable empty state; first-run discovery; no speculative features | ✅ PASS | FR-018, FR-029; catalog deferred per constitution guidance |

**All gates pass. No Complexity Tracking violations.**

## Project Structure

### Documentation (this feature)

```text
specs/001-mcp-config-management/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── AgentAdapter.md
├── checklists/
│   └── requirements.md
├── notes.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
mcp-inator/                          # Xcode project root
├── mcp-inator.xcodeproj/
├── mcp-inator/                      # App target
│   ├── App/
│   │   ├── mcp_inatorApp.swift      # @main, NSStatusItem setup
│   │   └── AppDelegate.swift
│   ├── UI/
│   │   ├── MenuBarView.swift        # Root popover content
│   │   ├── ConfigLibraryView.swift  # Config list + empty state
│   │   ├── AddEditConfigView.swift  # Add/edit form (US1)
│   │   ├── AgentListView.swift      # Per-agent enable/disable (US2/US3)
│   │   ├── DiscoveryView.swift      # First-run / new agent (US5)
│   │   ├── ImportReviewView.swift   # Per-entry import diff UI (US7)
│   │   └── PropagationView.swift    # Edit propagation prompt (US6)
│   ├── Models/
│   │   ├── MCPServerConfig.swift    # Canonical config entity
│   │   ├── AgentRecord.swift        # Persisted agent record
│   │   └── ConfigAgentAssignment.swift
│   ├── Store/
│   │   ├── ConfigStore.swift        # GRDB database access layer
│   │   └── Migrations/              # GRDB schema migrations
│   ├── Adapters/
│   │   ├── AgentAdapter.swift       # Protocol definition
│   │   ├── ClaudeCodeAdapter.swift
│   │   ├── ClaudeDesktopAdapter.swift
│   │   ├── GeminiCLIAdapter.swift
│   │   └── CodexCLIAdapter.swift
│   └── Resources/
│       └── Assets.xcassets
└── mcp-inatorTests/
    ├── Unit/
    │   ├── ServerKeyTransformTests.swift
    │   ├── ConfigStoreTests.swift
    │   └── SensitiveFieldTests.swift
    └── Integration/
        ├── Fixtures/
        │   ├── claude_code_config.json
        │   ├── claude_desktop_config.json
        │   ├── gemini_config.json
        │   └── codex_config.json
        ├── ClaudeCodeAdapterTests.swift
        ├── ClaudeDesktopAdapterTests.swift
        ├── GeminiCLIAdapterTests.swift
        └── CodexCLIAdapterTests.swift
```

**Structure Decision**: Native macOS Xcode project (single target). No backend, no web
frontend. Adapter-per-agent pattern isolates all format-specific logic. Integration tests
use fixture JSON files so they run without any real agent installation.

## Complexity Tracking

> No violations — all gates pass.
