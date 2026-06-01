# Feature Specification: Library Search & Filter

**Feature Branch**: `014-library-search`

**Created**: 2026-06-01

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Find a Server by Name (Priority: P1)

A user has 15–20 MCP servers in their library. They want to open a specific server's settings — say, their Postgres server — but don't want to scroll through the whole list to find it. They click into the search field at the top of the Servers tab, type "post", and the list immediately narrows to only matching servers. They click the one they want.

**Why this priority**: This is the entire value of the feature — fast, frictionless lookup. Everything else is polish around this core flow.

**Independent Test**: Add 10+ servers to the library. Type part of a server name in the search bar. Verify only matching entries appear immediately. Clear the field and verify all servers return.

**Acceptance Scenarios**:

1. **Given** the Servers tab is open with multiple servers, **When** the user types into the search bar, **Then** the list filters live to show only servers whose name or command contains the typed text (case-insensitive).
2. **Given** a search is active, **When** the user clears the search field, **Then** all servers are shown again.
3. **Given** a search term matches no servers, **When** the user types it, **Then** an empty-state message is shown rather than a blank list.
4. **Given** a search is active, **When** the user navigates to another tab and returns, **Then** the search is cleared and all servers are shown.

---

### User Story 2 — Find a Server by Command or Description (Priority: P2)

A user can't remember what they named their Stripe server but knows it uses `npx` and something about payments. They type "stripe" and it appears. Alternatively they type "npx" and see all npm-based servers grouped visually.

**Why this priority**: Matching on command/description is a natural extension that costs little once name-matching exists, and covers the case where users don't remember exact names.

**Independent Test**: Add a server with an unusual display name but a recognizable command (e.g., display name "Payments" with command `npx stripe-mcp`). Search for "stripe" — it should appear. Search for the display name — it should also appear.

**Acceptance Scenarios**:

1. **Given** a server whose display name doesn't match the query, **When** the user searches for part of its command string, **Then** that server appears in results.
2. **Given** multiple servers share a common command prefix (e.g., all use `npx`), **When** the user types that prefix, **Then** all matching servers appear.

---

### Edge Cases

- What happens when the library is empty? The search bar should still appear but show the existing empty-library state.
- What happens when only one server is in the library? Search still works correctly; filtering to zero results shows the empty-state message.
- Very long search strings: no crash; just filter normally (likely zero results).
- Special characters in the search field: treated as literal text, not regex.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Servers tab MUST display a search input field in the toolbar area, consistent in placement and visual style with the search field in the Catalog tab.
- **FR-002**: As the user types, the server list MUST filter live (no submit required) to show only servers matching the query.
- **FR-003**: Matching MUST be case-insensitive and check both the server's display name and its command string.
- **FR-004**: When the search field is empty, ALL servers MUST be shown (normal unfiltered state).
- **FR-005**: When the search term matches no servers, an empty-state message MUST be shown (e.g., "No servers match your search").
- **FR-006**: When the user leaves the Servers tab and returns, the search MUST be reset to empty.
- **FR-007**: The search field MUST be clearable with a single action (e.g., clicking the × button inside the field or pressing Escape).

### Key Entities

- **MCPServerConfig**: The existing server model — display name, command, description (if present). No new fields required.
- **Search query**: A transient, in-memory string — not persisted between sessions or tab switches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with 20 servers in their library can locate any specific server in under 5 seconds by typing its name.
- **SC-002**: The list updates within one animation frame of each keystroke — no perceptible lag.
- **SC-003**: Zero existing library functionality is broken (editing, enabling/disabling, reordering) when search is active or inactive.

## Assumptions

- Search state is ephemeral — it resets when leaving the tab, not persisted to disk or UserDefaults.
- Drag-to-reorder is disabled while a search is active (can't meaningfully reorder a filtered subset).
- The feature applies to both menu bar mode and dock mode Servers lists.
- No server-count threshold — the search bar is always visible, even with 0 or 1 servers, for consistency.
