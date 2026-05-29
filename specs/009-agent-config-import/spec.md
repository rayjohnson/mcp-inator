# Feature Specification: Import MCP Servers from Agent Config Files

**Feature Branch**: `009-agent-config-import`

**Created**: 2026-05-29

**Status**: Draft

**Input**: GitHub Issue #5 — "Users who already have MCP servers configured in Claude Desktop or other agent configs have to re-enter them all manually into the mcp-inator library. A one-click import would eliminate this friction on day 2."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — New User Imports from Claude Desktop (Priority: P1)

A user who already has MCP servers configured in Claude Desktop opens mcp-inator for the first time. They see an "Import…" menu in the Servers tab and choose "Claude Desktop." mcp-inator reads the Claude Desktop config file, categorises each server as New, Already in Library, or Conflict, and presents a review screen. The user selects which servers to import and clicks Import — the servers appear in their library immediately, without any manual re-entry.

**Why this priority**: This is the primary friction point for all new users arriving with an existing Claude Desktop setup. Removing it makes the onboarding experience dramatically smoother.

**Independent Test**: Install Claude Desktop with two MCP servers configured → open mcp-inator (without any prior agent discovery or registration) → click Import… → choose Claude Desktop → confirm both servers appear in the review screen → import → confirm both are now in the Servers tab library.

**Acceptance Scenarios**:

1. **Given** Claude Desktop is installed with a populated config file, **When** the user opens the Servers tab, **Then** "Import…" appears and Claude Desktop is listed as an importable source — even if the user has never registered Claude Desktop as a managed agent.

2. **Given** the user selects "Claude Desktop" from the Import menu, **When** the review screen opens, **Then** each discovered MCP server is categorised as New, Already in Library (exact match), or Conflict (key exists but config differs).

3. **Given** the review screen is showing, **When** the user clicks "Import Selected," **Then** only the checked/selected entries are added to the library and the user returns to the Servers tab.

4. **Given** Claude Desktop config has a server whose key already exists in the library with identical configuration, **When** the review screen opens, **Then** that server appears in "Already in Library" and is pre-deselected (nothing to import).

5. **Given** Claude Desktop is installed but its config file is empty or contains no MCP servers, **When** the user chooses it from Import, **Then** the review screen shows an empty-state message ("No MCP servers found in Claude Desktop") rather than crashing or silently doing nothing.

---

### User Story 2 — Import from Gemini CLI (Priority: P1)

A user with MCP servers configured in Gemini CLI wants to bring those same servers into mcp-inator. They use the same Import… menu, choose Gemini CLI, and go through the identical review-and-select flow as Claude Desktop. The experience is indistinguishable from importing from Claude Desktop.

**Why this priority**: Gemini CLI uses the same config format as Claude Desktop — the implementation cost is near-zero and the user value is identical.

**Independent Test**: Configure one MCP server in Gemini CLI's config file → open mcp-inator → Import… → Gemini CLI → confirm server appears in review → import → confirm it appears in the Servers tab.

**Acceptance Scenarios**:

1. **Given** Gemini CLI is installed with a populated config file, **When** the user opens the Import menu, **Then** "Gemini CLI" appears as an importable source regardless of whether it has been registered as a managed agent.

2. **Given** the user selects "Gemini CLI," **When** the review screen opens, **Then** the same categorisation (New / Already in Library / Conflict) applies as for Claude Desktop.

---

### User Story 3 — Gemini Desktop Shows as "Managed In-App" (Priority: P2)

A user who has Gemini Desktop installed opens the Import menu and sees "Gemini Desktop" listed, but greyed out with a note explaining that Gemini Desktop manages its MCP servers internally and cannot be imported from. The user understands why the option is unavailable rather than wondering why it's missing.

**Why this priority**: Silently hiding Gemini Desktop from the Import menu will confuse users who know it's installed and expect to see it. An honest, explained disabled state is better than a missing option.

**Independent Test**: Install Gemini Desktop → open Import menu → confirm "Gemini Desktop" appears but is disabled/greyed → confirm a tooltip or inline label explains "MCP servers are managed inside the Gemini app."

**Acceptance Scenarios**:

1. **Given** Gemini Desktop is installed, **When** the Import menu opens, **Then** "Gemini Desktop" appears in the list in a visually distinct disabled state (greyed label or lock icon).

2. **Given** the user hovers or focuses the disabled Gemini Desktop entry, **When** the tooltip or helper text is visible, **Then** it explains that Gemini Desktop manages MCP servers internally and import is not available.

3. **Given** Gemini Desktop is not installed, **When** the Import menu opens, **Then** Gemini Desktop does not appear at all (not installed = not shown).

---

### User Story 4 — Import Shows All Installed Agents, Not Just Registered Ones (Priority: P1)

The Import menu surfaces every locally installed agent that has a readable config file — including agents the user has never registered in mcp-inator. A brand-new user who opens mcp-inator for the first time and has Claude Desktop, Gemini CLI, and Codex CLI all installed should see all three in the Import menu immediately, with no prerequisite steps.

**Why this priority**: Without this, the import feature only works for users who have already gone through agent discovery/registration — defeating the purpose of easing onboarding for new users.

**Acceptance Scenarios**:

1. **Given** a fresh mcp-inator install with no agents registered, **When** the Servers tab loads, **Then** the Import menu lists every locally installed agent with a readable config file.

2. **Given** an agent is installed but has an inaccessible or missing config file, **When** the Import menu is built, **Then** that agent is excluded from the list (not shown as importable).

---

### Edge Cases

- What if an agent's config file exists but cannot be parsed (corrupted JSON)? The agent appears in the Import menu, but selecting it shows an error message in the review screen explaining the file could not be read.
- What if the same server key appears in multiple agent config files the user imports from in sequence? Each import is independent; the second import will show it as a Conflict if the configs differ.
- What if the user imports a server and then edits it in mcp-inator — then imports from the same agent again? The edited version in the library will show as a Conflict against the original on-disk config.
- What if no agent is installed at all? The "Import…" menu button is hidden entirely (current behaviour preserved).
- What if an agent is installed but has zero MCP servers in its config? It still appears in the Import menu; clicking it shows the empty-state "No MCP servers found" screen.

## Requirements *(mandatory)*

### Functional Requirements

**Import Source Discovery (US4)**

- **FR-001**: The system MUST detect importable agents by scanning all known adapter types for installation (`isInstalled()`) and config-file accessibility at launch and whenever the Import menu is opened — independent of whether those agents are registered in the mcp-inator agent database.
- **FR-002**: An agent MUST appear in the Import menu if and only if: it is installed AND its config file exists AND it is not app-managed (`isAppManaged == false`).
- **FR-003**: The Import menu MUST be hidden when no importable agents are found.

**App-Managed Agent Display (US3)**

- **FR-004**: An installed app-managed agent (currently only Gemini Desktop) MUST appear in the Import menu in a disabled state when installed, with a visible explanation that its MCP servers are managed internally.
- **FR-005**: An app-managed agent that is not installed MUST NOT appear in the Import menu.

**Import Review Flow (US1, US2)**

- **FR-006**: Selecting an importable agent from the Import menu MUST open the existing `ImportReviewView` populated with entries categorised as: New, Already in Library (exact match), or Conflict (key exists, config differs).
- **FR-007**: "New" entries MUST be pre-selected for import by default.
- **FR-008**: "Already in Library" entries MUST be pre-deselected and shown as informational only.
- **FR-009**: "Conflict" entries MUST be pre-deselected, showing both the library version and the on-disk version so the user can choose which to keep.
- **FR-010**: The "Import Selected" button MUST be disabled when zero entries are selected.
- **FR-011**: Confirming import MUST add selected servers to the mcp-inator library without registering the source agent or modifying the source agent's config file.

**Error Handling**

- **FR-012**: If a config file cannot be parsed, the review screen MUST display a human-readable error message and offer a "Back" action — no crash, no silent failure.
- **FR-013**: Import MUST NOT create duplicate library entries; the categorisation step prevents this by detecting existing keys before any write occurs.

### Key Entities

- **ImportSource**: A detected installed agent with a readable config file; carries display name, agent type, and whether it is importable or disabled (app-managed).
- **ImportCategory**: Classification of each discovered MCP server entry — New, ExactMatch, or Conflict (already exists in the codebase as `ConfigStore.ImportCategory`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with Claude Desktop already configured can import all their existing MCP servers into mcp-inator in under 60 seconds, with no manual data entry.
- **SC-002**: The Import menu correctly lists all installed, file-backed agents on the first launch of mcp-inator, with no prior agent registration required.
- **SC-003**: Zero duplicate library entries result from importing the same agent config twice.
- **SC-004**: All categorisation decisions (New / Already in Library / Conflict) are correct in 100% of test cases across Claude Desktop, Claude Code, Gemini CLI, and Codex CLI.
- **SC-005**: Gemini Desktop (when installed) is correctly shown as disabled in the Import menu with an explanation visible to the user.

## Assumptions

- The config file formats for Claude Desktop, Claude Code, Gemini CLI, and Codex CLI all use the existing `readConfigs(from:)` implementations — no format changes are needed.
- Gemini Desktop's MCP configuration remains stored in an internal SQLite database with no exported JSON file; direct import is not feasible without SQLite access.
- Import only flows one direction: from agent config files into the mcp-inator library. The reverse (pushing library changes back to agent configs) is handled by the existing "Push Changes" propagation feature and is out of scope here.
- Importing a server does not automatically enable it for any agent — the user enables per-agent assignments separately after import.
- The existing `ImportReviewView` UI and `ConfigStore.categorizeImport(from:configPath:)` logic are reused without structural changes; only the source-discovery step changes.
