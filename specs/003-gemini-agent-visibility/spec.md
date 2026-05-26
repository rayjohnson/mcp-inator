# Feature Specification: Gemini Desktop Support + Agent Visibility Controls

**Feature Branch**: `003-gemini-agent-visibility`

**Created**: 2026-05-26

**Status**: Draft

**Input**: GitHub Issue #3 — "I've now installed the Gemini desktop app - it should also be supported as a new agent. The number of potential agents will continue to grow... In the Servers side we show the icon (and status) for all POSSIBLE AI Agents. That list will get too big at some point... I think we should have the ability to 'turn off' agents the user really doesn't use. If they are turned off then the icon should not show up in the other places."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Gemini Desktop Appears as a Detected Agent (Priority: P1)

A user who has the Gemini Desktop macOS app installed opens mcp-inator and sees "Gemini Desktop" listed in the Agents tab. They can tap the row to see a clear status message explaining that Gemini Desktop manages its MCP servers internally — mcp-inator cannot read or write its config. The entry in the Agents tab reflects that the app is installed.

**Background**: Gemini Desktop supports MCP (confirmed via binary analysis), but only HTTP/Streamable-HTTP transport. Its MCP configuration is stored in the app's internal SQLite database — there is no external JSON config file mcp-inator can read or write. This is different from all other supported agents.

**Why this priority**: The user installed Gemini Desktop and expects it to appear in mcp-inator. An agent that is silently absent creates confusion. Showing it with an honest "managed in-app" status is better than pretending it doesn't exist.

**Independent Test**: Open mcp-inator with `/Applications/Gemini.app` present → navigate to Agents tab → confirm "Gemini Desktop" row appears with status indicator → tap to open agent view → confirm "in-app managed" banner is shown (not "config file not accessible") → confirm no MCP server toggle list is shown.

**Acceptance Scenarios**:

1. **Given** `/Applications/Gemini.app` is installed, **When** mcp-inator launches and scans for agents, **Then** an `AgentRecord` with `agentType = .geminiDesktop` and `displayName = "Gemini Desktop"` exists in the DB.

2. **Given** the Gemini Desktop agent row is tapped, **When** `AgentListView` opens, **Then** an "in-app managed" banner is shown explaining that MCP servers are configured directly in the Gemini app — with no server toggle list and no "Change Path" button.

3. **Given** `/Applications/Gemini.app` is not installed, **When** mcp-inator scans for agents, **Then** no `geminiDesktop` agent record is created.

4. **Given** the Gemini Desktop agent exists, **When** it appears in the Servers tab agent badge row, **Then** a Gemini Desktop badge is shown with an "in-app" or neutral state (not green/red availability indicator).

---

### User Story 2 — Hide Agents You Don't Use (Priority: P1)

A user who only actively uses Claude Code and Gemini CLI wants to hide Claude Desktop, Codex CLI, and Gemini Desktop from the UI, so the agent badges in the Servers tab are less cluttered and the Agents list is shorter. They can toggle visibility per-agent and restore hidden agents at any time without losing any config.

**Why this priority**: As the number of supported agents grows, users who only use 2-3 agents will see badges for agents they've never touched. This is visual noise that degrades the core library view.

**Independent Test**: With agents shown — Claude Code, Claude Desktop, Gemini CLI, Codex CLI, Gemini Desktop — hide "Codex CLI" → verify no Codex CLI badge appears in any Servers tab config row → navigate to Agents tab → verify Codex CLI row is not shown in the main list → unhide via Manage → verify Codex CLI reappears everywhere.

**Acceptance Scenarios**:

1. **Given** the Agents tab is open, **When** the user taps the toolbar "Manage" button, **Then** a view appears showing all agents with their current visibility state as a toggle.

2. **Given** an agent is hidden, **When** viewing any MCP server row in the Servers tab (ConfigLibraryView), **Then** no badge or icon for that agent appears in the row.

3. **Given** an agent is hidden, **When** viewing the Agents tab, **Then** that agent's row is not shown in the main list (visible agents only).

4. **Given** an agent is hidden, **When** the user opens Manage Agents and re-enables it, **Then** the agent's badges immediately reappear in the Servers tab and its row returns in the Agents tab — with all assignment states intact (no data loss).

5. **Given** all agents are hidden, **When** viewing the Agents tab, **Then** an empty state explains that all agents are hidden with a "Manage" link.

6. **Given** an agent is hidden, **When** viewing PropagationView (the "apply to agents" screen after saving a config), **Then** the hidden agent does not appear as an option. Visibility is a global preference — hidden means "I don't want to manage this agent."

---

### Edge Cases

- What happens when Gemini Desktop is installed *after* mcp-inator first launches? The app scans for new agents on each launch; the new record will be created on the next startup.
- What if a user hides every agent? The Agents tab shows an empty state with a "Manage" action — no orphaned UI.
- What if an agent is hidden while the `AgentsTabView` is visible? The list should update reactively via `@Published` state.
- What about the DiscoveryView "New Agents Found" onboarding sheet? All agents (including hidden) appear in discovery so users can make an informed choice during first run. Visibility does not affect discovery.
- Can you hide Gemini Desktop even though it's "in-app managed"? Yes — visibility is independent of manageability.

## Requirements *(mandatory)*

### Functional Requirements

**Gemini Desktop Adapter (US1)**

- **FR-001**: System MUST add `AgentType.geminiDesktop` to the `AgentType` enum with `rawValue = "gemini_desktop"` and `displayName = "Gemini Desktop"`.
- **FR-002**: System MUST implement `GeminiDesktopAdapter` conforming to `AgentAdapter`, detecting installation via `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS")` with `/Applications/Gemini.app` as fallback.
- **FR-003**: `AgentAdapter` protocol MUST gain `var isAppManaged: Bool { get }` with a default implementation returning `false`. `GeminiDesktopAdapter` returns `true`.
- **FR-004**: `GeminiDesktopAdapter.readConfigs(from:)` MUST return an empty dict (no-op). `writeConfigs` and `removeConfig` MUST return `.success` without writing anything.
- **FR-005**: `AgentListView` MUST check `adapter.isAppManaged` and, when `true`, show an "in-app managed" banner (instead of the "unavailable" banner or toggle list).
- **FR-006**: `AgentIcon` MUST load the real Gemini Desktop app icon for `.geminiDesktop` via `NSWorkspace` (same pattern as Claude Desktop), falling back to a blue "G" `LetterBadge`.
- **FR-007**: All sites that switch on `AgentType` or construct adapters MUST be updated to include `.geminiDesktop`.
- **FR-008**: `GeminiDesktopAdapter.defaultConfigPath()` returns a sentinel path (`~/Library/Application Support/Google/Gemini/mcp_servers.json`) that will not exist. `isAvailable` is always `false` for this adapter. The path is not shown as user-editable.

**Agent Visibility Controls (US2)**

- **FR-009**: `AgentRecord` MUST gain an `isVisible: Bool` field (default `true`), persisted in the `agents` table via a new GRDB migration.
- **FR-010**: `ConfigStore` MUST expose `func setAgentVisibility(agentId: Int64, visible: Bool) throws`.
- **FR-011**: `ConfigStore` MUST expose `var visibleAgents: [AgentRecord]` (computed/filtered from `agents`, where `isVisible == true`).
- **FR-012**: `AgentsTabView` MUST use `store.visibleAgents` for its list. `store.agents` remains the full unfiltered set.
- **FR-013**: `ConfigLibraryView` (Servers tab) MUST only show agent badges for agents where `isVisible == true`.
- **FR-014**: A "Manage Agents" view MUST be reachable from the Agents tab toolbar (gear icon). It shows all agents — including hidden ones — with a visibility toggle per row. Toggling persists immediately.
- **FR-015**: `PropagationView` MUST only list agents where `isVisible == true`.
- **FR-016**: Hiding an agent MUST NOT delete any `AgentRecord`, `ConfigAgentAssignment`, or `MCPServerConfig`.
- **FR-017**: The Agents tab MUST show an empty state with a "Manage" action when `store.visibleAgents` is empty.

### Key Entities *(include if feature involves data)*

- **`AgentRecord`** — gains `isVisible: Bool` (default `true`). All other fields unchanged.
- **`GeminiDesktopAdapter`** — new `struct` conforming to `AgentAdapter`. Detection-only; `isAppManaged = true`; no file reads or writes.
- **`AgentType`** — gains `.geminiDesktop` case.
- **`AgentAdapter` protocol** — gains optional `isAppManaged: Bool` property (default `false`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `/Applications/Gemini.app` present → "Gemini Desktop" agent row appears in Agents tab on next launch with an in-app-managed banner on tap.
- **SC-002**: Hiding 2 of 5 agents reduces agent badge columns in Servers tab from 5 to 3 with no page reload.
- **SC-003**: Unhiding a previously-hidden agent restores all its badges and assignment states without requiring any re-toggle.
- **SC-004**: `make test` passes with new adapter and visibility tests green.

## Assumptions

- Gemini Desktop's MCP config is stored in its internal SQLite database; there is no file-based config path mcp-inator can write. This is provisional — if Google publishes a file-based path, only `GeminiDesktopAdapter` needs updating.
- Agent visibility is a per-device preference (stored in the local DB, not synced).
- Hiding an agent hides it consistently across Agents tab, Servers tab badges, and PropagationView.
- The DiscoveryView "New Agents Found" sheet is not filtered by visibility — newly-found agents always appear in the discovery flow.
- macOS only; no mobile or cross-platform scope.
