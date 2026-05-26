# Developer Quickstart: MCP Server Configuration Management

**Date**: 2026-05-25 | **Plan**: [plan.md](plan.md)

For a new developer getting oriented on this feature.

---

## What This Feature Does

mcp-inator is a macOS menubar app. You add an MCP server config once; the app writes it to
whichever AI agent config files you choose. This feature (Spec 001) is the core:
add/edit/delete configs, enable/disable per agent, first-run discovery, and import from
existing agent files.

---

## Repository Layout

```
mcp-inator/                              Root: Xcode project
├── mcp-inator.xcodeproj/
├── mcp-inator/                          App target
│   ├── App/
│   │   ├── mcp_inatorApp.swift          @main entry, NSStatusItem setup
│   │   └── AppDelegate.swift
│   ├── UI/
│   │   ├── MenuBarView.swift            Root popover
│   │   ├── ConfigLibraryView.swift      Config list + empty state (US1, US4)
│   │   ├── AddEditConfigView.swift      Add / edit form (US1)
│   │   ├── AgentListView.swift          Enable / disable per agent (US2, US3)
│   │   ├── DiscoveryView.swift          First-run scan (US5)
│   │   ├── ImportReviewView.swift       Per-entry import with diffs (US7)
│   │   └── PropagationView.swift        Edit propagation prompt (US6)
│   ├── Models/
│   │   ├── MCPServerConfig.swift        Canonical config entity
│   │   ├── AgentRecord.swift            Persisted agent + AgentType enum
│   │   └── ConfigAgentAssignment.swift  Enable/disable state
│   ├── Store/
│   │   ├── ConfigStore.swift            All database access (GRDB)
│   │   └── Migrations/                  Numbered migration files
│   └── Adapters/
│       ├── AgentAdapter.swift           Protocol + supporting types
│       ├── ClaudeCodeAdapter.swift
│       ├── ClaudeDesktopAdapter.swift
│       ├── GeminiCLIAdapter.swift
│       └── CodexCLIAdapter.swift        Reads/writes TOML (via TOMLKit)
└── mcp-inatorTests/
    ├── Unit/
    │   ├── ServerKeyTransformTests.swift
    │   ├── ConfigStoreTests.swift
    │   └── SensitiveFieldTests.swift
    └── Integration/
        ├── Fixtures/                    Static JSON/TOML files for adapter tests
        ├── ClaudeCodeAdapterTests.swift
        ├── ClaudeDesktopAdapterTests.swift
        ├── GeminiCLIAdapterTests.swift
        └── CodexCLIAdapterTests.swift
```

---

## Key Concepts

### Canonical Store vs. Derived Outputs

The SQLite database (GRDB) is the single source of truth. Agent config files (`~/.claude.json`,
`~/.codex/config.toml`, etc.) are **derived outputs** written by adapters. mcp-inator never
reads agent files except for: (a) pre-flight diff check before a write, and (b) import flow.

### Server Key vs. Display Name

Every config has two name fields:
- **Display name** — shown only inside mcp-inator UI, free-form
- **Server key** — the JSON/TOML key written to agent config files; auto-populated from
  display name (lowercase, spaces→hyphens, strip non-alphanumeric-and-hyphen), always editable

### Adapter Pattern

Each of the four agents has a concrete `AgentAdapter` implementation. All format differences
(JSON vs. TOML, different config file paths, agent-specific key constraints) are isolated
inside the adapter. The rest of the app never knows whether it's writing JSON or TOML.

### Pre-flight Diff Check

Before any write, the adapter reads the current on-disk state. If it differs from what
mcp-inator last wrote (i.e., the file was edited externally), a diff is shown and the user
must confirm before mcp-inator overwrites. This prevents silent clobbering of manual edits.

### Atomic Writes

All file writes use the temp-file-then-rename pattern (`FileManager.replaceItem`). A crash
mid-write leaves the original file intact.

---

## Agent Config File Locations

| Agent | Default config path | Format |
|-------|-------------------|--------|
| Claude Code CLI | `~/.claude.json` | JSON |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | JSON |
| Gemini CLI | `~/.gemini/settings.json` | JSON |
| Codex CLI | `~/.codex/config.toml` | TOML |

---

## Things That Will Bite You

1. **Codex is TOML, not JSON.** `CodexCLIAdapter` is the odd one out. It uses TOMLKit.
   All other adapters use `JSONSerialization`.

2. **Gemini rejects underscores in server keys.** Our default auto-population rule
   (hyphens) is already compliant, but `GeminiCLIAdapter.validateServerKey` must explicitly
   reject `_` and surface a validation error.

3. **Claude Code reserves the key `workspace`.** `ClaudeCodeAdapter.validateServerKey`
   must reject it with a clear message.

4. **No sandbox.** The app is distributed unsandboxed (GitHub/Homebrew). It does NOT need
   Security-Scoped Bookmarks or NSOpenPanel for writing to `~/Library/Application Support/`.
   Developer ID + Hardened Runtime + notarization is required.

5. **All agents require restart.** FR-022 fires a notification after every write.
   For Gemini, the notification should mention `/mcp reload` as an alternative.

6. **Env var sensitivity heuristic.** Values matching `${VAR_NAME}` are not sensitive
   (they're references, not secrets). Everything else is sensitive by default and masked in UI.

---

## Development Prerequisites

- Xcode 15+ (Swift 5.9+)
- macOS 13.0 (Ventura) deployment target
- Swift Package Manager dependencies:
  - [GRDB.swift](https://github.com/groue/GRDB.swift) 6.x — SQLite store
  - [Sparkle](https://github.com/sparkle-project/Sparkle) 2.x — auto-update
  - [TOMLKit](https://github.com/LebJe/TOMLKit) — Codex TOML support

## Running Tests

Integration tests use fixture files in `mcp-inatorTests/Integration/Fixtures/` — no real
agent installation required. Tests must NOT read or write to `~/.claude.json` or any real
agent config path.

```bash
xcodebuild test -scheme mcp-inator -destination 'platform=macOS'
```

---

## Where to Start

If you're implementing a new feature:
1. Read `specs/001-mcp-config-management/spec.md` for requirements
2. Read `data-model.md` for the entity model and DB schema
3. Read `contracts/AgentAdapter.md` for the adapter protocol

If you're fixing a bug in an adapter:
1. Add or update the integration test in `mcp-inatorTests/Integration/<Agent>AdapterTests.swift`
2. Update the fixture file in `Fixtures/` if the expected format changed
3. Fix the adapter; verify the pre-flight diff check and atomic write path are intact
