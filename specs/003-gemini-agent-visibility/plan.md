# Implementation Plan: Gemini Desktop Support + Agent Visibility Controls

**Branch**: `003-gemini-agent-visibility` | **Date**: 2026-05-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-gemini-agent-visibility/spec.md`

## Summary

Add the Gemini Desktop macOS app as a fifth detected agent (detection-only: the app manages MCP internally via HTTP, mcp-inator cannot write its config). Introduce per-agent visibility controls so users can hide agents they don't use from the Servers tab badges, Agents tab list, and PropagationView. Both features are additive: a new adapter struct with `isAppManaged = true`, a GRDB migration for `isVisible`, a new `ManageAgentsView`, and targeted updates to existing views.

**Key constraint**: Gemini Desktop uses HTTP/Streamable-HTTP transport only; its MCP config is stored in an internal SQLite DB. `GeminiDesktopAdapter` is a no-op for reads and writes — it exists solely for detection and consistent UI representation.

## Technical Context

**Language/Version**: Swift 5.9, SwiftUI, macOS 13+

**Primary Dependencies**: GRDB (SQLite ORM), SwiftUI, AppKit (NSWorkspace for app detection and icon loading)

**Storage**: SQLite via GRDB — `agents` table gains `isVisible INTEGER NOT NULL DEFAULT 1` column via `Migration004`

**Testing**: XCTest (`make test`) — new unit tests for `GeminiDesktopAdapter` detection and `AgentVisibility` store methods

**Target Platform**: macOS 13+ (same as existing app)

**Project Type**: macOS desktop app (MenuBarExtra / status bar)

**Performance Goals**: Visibility toggle feels instantaneous (< 1 frame). No new network calls.

**Constraints**:
- Non-destructive: hiding an agent must never delete DB records
- `GeminiDesktopAdapter` must never write to disk
- `AgentAdapter` protocol extension must not break existing adapters

**Scale/Scope**: 5 agents total post-feature. Small, focused change: 1 new Swift file (adapter), 1 new Swift file (ManageAgentsView), 1 new migration, 1 new protocol property, targeted edits to ~7 existing files.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | ✓ PASS | `NSWorkspace` detection, NavigationLink-based ManageAgentsView, no new window types |
| II. Single Source of Truth | ✓ PASS | `isVisible` stored in existing DB; Gemini Desktop shown honestly as unmanageable |
| III. Non-Destructive Configuration | ✓ PASS | Hiding sets `isVisible = false`; no records deleted (FR-016). `GeminiDesktopAdapter` never writes |
| IV. Config Portability | ✓ PASS | New adapter conforms to `AgentAdapter`; no core store changes |
| V. Simplicity & Discoverability | ✓ PASS | ManageAgentsView accessible from toolbar (one tap); "in-app managed" banner is self-explanatory |

No violations. No complexity tracking required.

## Project Structure

### Documentation (this feature)

```text
specs/003-gemini-agent-visibility/
├── plan.md              # This file
├── spec.md              # Feature specification (updated for Option A)
├── research.md          # Binary analysis findings + design decisions
├── data-model.md        # Entity changes, migration, store API
├── quickstart.md        # Build/test/use guide
├── contracts/
│   ├── GeminiDesktopAdapter.md   # Detection-only adapter contract
│   └── AgentVisibility.md        # Visibility API contract
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code

```text
mcp-inator/
├── Adapters/
│   ├── AgentAdapter.swift           # EDIT: add isAppManaged: Bool { false } default
│   ├── ClaudeCodeAdapter.swift      # unchanged
│   ├── ClaudeDesktopAdapter.swift   # unchanged
│   ├── CodexCLIAdapter.swift        # unchanged
│   ├── GeminiCLIAdapter.swift       # unchanged
│   ├── GeminiDesktopAdapter.swift   # NEW (detection-only, isAppManaged = true)
│   └── StringExtensions.swift       # unchanged
├── Models/
│   └── AgentRecord.swift            # EDIT: .geminiDesktop case + isVisible field
├── Store/
│   ├── ConfigStore.swift            # EDIT: visibleAgents, setAgentVisibility, fetchStatusMatrix filter
│   └── Migrations/
│       ├── Migration001–003.swift   # unchanged
│       └── Migration004.swift       # NEW: isVisible column
├── UI/
│   ├── AgentIcon.swift              # EDIT: .geminiDesktop → load app icon
│   ├── AgentListView.swift          # EDIT: isAppManaged banner + .geminiDesktop adapter case
│   ├── ConfigLibraryView.swift      # unchanged (badge filtering is transparent via store)
│   ├── DiscoveryView.swift          # EDIT: add GeminiDesktopAdapter to adapters dict
│   ├── ManageAgentsView.swift       # NEW
│   ├── MenuBarView.swift            # EDIT: allAdapters + Agents tab toolbar → ManageAgentsView
│   └── PropagationView.swift        # EDIT: use store.visibleAgents
└── App/
    └── mcp_inatorApp.swift          # EDIT: add GeminiDesktopAdapter to scan list

mcp-inatorTests/
└── Unit/
    ├── GeminiDesktopAdapterTests.swift  # NEW
    └── AgentVisibilityTests.swift       # NEW
```

## Implementation Phases

### Phase 1: Protocol + Model + Adapter (blocks everything)

1. Add `var isAppManaged: Bool { false }` default to `AgentAdapter` protocol extension
2. Add `AgentType.geminiDesktop` case to `AgentRecord.swift`
3. Add `isVisible` field to `AgentRecord` (struct + GRDB encode/init)
4. Create `Migration004.swift`; register in `ConfigStore`
5. Create `GeminiDesktopAdapter.swift`
6. Add `.geminiDesktop` to all switch/adapter-map sites (AgentListView, AgentIcon, DiscoveryView, MenuBarView.allAdapters, mcp_inatorApp)

### Phase 2: AgentListView "in-app managed" Banner

7. Add `isAppManaged` branch to `AgentListView.body` rendering logic
8. Add restart-message no-op for `.geminiDesktop` (banner replaces the restart notice flow)

### Phase 3: Visibility UI

9. Add `visibleAgents` computed property and `setAgentVisibility()` to `ConfigStore`
10. Update `fetchStatusMatrix()` to filter by `isVisible = 1`
11. Update `AgentsTabView` to use `store.visibleAgents`; add empty state for all-hidden case
12. Update `PropagationView` to use `store.visibleAgents`
13. Create `ManageAgentsView.swift`
14. Add toolbar "Manage" button to `AgentsTabView` → `ManageAgentsView`

### Phase 4: Tests

15. Create `GeminiDesktopAdapterTests.swift` (isInstalled detection, no-op read/write, isAppManaged)
16. Create `AgentVisibilityTests.swift` (setAgentVisibility, visibleAgents filter, fetchStatusMatrix filter)

### Phase 5: Polish

17. Verify `AgentIcon` for `.geminiDesktop` shows real app icon
18. Verify `DiscoveryView` surfaces Gemini Desktop in "New Agents Found" flow
19. Run `make test`; verify all green
20. Manual end-to-end: hide agent → badges gone → unhide → badges back; Gemini Desktop shows in-app banner

## Complexity Tracking

No constitution violations — no complexity tracking required.
