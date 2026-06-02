# Feature Specification: Zed Editor MCP Adapter

**Feature Branch**: `015-zed-adapter`

**Created**: 2026-06-01

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Install an MCP Server to Zed (Priority: P1)

A user who uses both Claude Code and Zed as their AI-assisted coding environment has already added several MCP servers through mcp-inator. They open mcp-inator, see Zed listed as a detected agent (alongside Claude Code), and can install any server to Zed with the same one-click flow they use for other agents. Zed is restarted and the server is available.

**Why this priority**: This is the core value — Zed users should be able to manage their MCP servers from mcp-inator without manually editing JSON config files.

**Independent Test**: Install Zed on the test machine so that Zed's settings file is present. Open mcp-inator and verify Zed appears in the agent list. Add an MCP server and select Zed as the target. Verify the server appears in Zed's settings file under `context_servers` with the correct structure.

**Acceptance Scenarios**:

1. **Given** Zed is installed (its settings file exists or app is present), **When** mcp-inator launches, **Then** Zed appears in the agents list as an available target.
2. **Given** Zed is shown as available, **When** the user installs an MCP server targeting Zed, **Then** the server entry is written to Zed's settings file under `context_servers` with the correct name, command path, args, and env vars.
3. **Given** Zed's settings file already contains other settings, **When** an MCP server is written, **Then** all existing settings are preserved.
4. **Given** an MCP server is installed to Zed, **When** the user removes it, **Then** the entry is removed from `context_servers` and all other settings remain intact.

---

### User Story 2 — Drift Detection for Zed Config (Priority: P2)

A user edited their Zed settings file manually (e.g., to adjust an arg) after mcp-inator had written an entry. When they try to update or remove that server through mcp-inator, they are warned that the config has changed externally rather than having their manual edit silently overwritten.

**Why this priority**: Zed power users are likely to edit their settings directly. Silent overwrites of manual edits would be a trust-breaking experience, consistent with how drift is handled for all other agents.

**Independent Test**: Write a server entry via mcp-inator to Zed's settings file. Manually edit that entry. Attempt to update it through mcp-inator. Verify a drift warning is shown instead of a silent overwrite.

**Acceptance Scenarios**:

1. **Given** an MCP server was installed to Zed, **When** the user modifies that entry directly in settings and then tries to update it in mcp-inator, **Then** a drift-detected warning is shown.
2. **Given** an MCP server was installed to Zed, **When** a different entry in `context_servers` is modified externally and the user updates an unrelated server, **Then** no drift warning is shown (only managed keys are compared).

---

### User Story 3 — Auto-Detection When Zed Is Not Installed (Priority: P3)

A user who does not have Zed installed does not see Zed in the agent list. If Zed is later installed, it appears on the next mcp-inator launch without any user action required.

**Why this priority**: Auto-detection on launch is the expected UX for all adapters — no manual registration should be required.

**Independent Test**: Verify Zed does not appear when its settings file and app bundle are absent. Create the settings file and restart mcp-inator — verify Zed now appears.

**Acceptance Scenarios**:

1. **Given** Zed is not installed (no settings file or app bundle found), **When** mcp-inator launches, **Then** Zed does not appear in the agents list.
2. **Given** Zed was not present on a previous launch, **When** the user installs Zed and restarts mcp-inator, **Then** Zed appears in the agents list automatically.

---

### Edge Cases

- What if `context_servers` key is absent from settings.json? It should be created on first write.
- What if settings.json exists but is empty or contains only `{}`?
- What if settings.json is malformed and cannot be parsed?
- What if two different agents (e.g., Claude Code and Zed) have a server with the same key name — are they managed independently?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect Zed as installed when either `~/.config/zed/settings.json` exists or the Zed app bundle is present at `/Applications/Zed.app`.
- **FR-002**: The system MUST read existing MCP server entries from the `context_servers` key in Zed's settings.json.
- **FR-003**: The system MUST write new MCP server entries to `context_servers` using the Zed-native structure: a `command` object with `path` and `args` fields, plus an optional `env` object.
- **FR-004**: The system MUST preserve all existing keys in settings.json (both inside and outside `context_servers`) when writing or removing entries.
- **FR-005**: The system MUST detect drift when a managed entry has been externally modified before allowing an update or removal.
- **FR-006**: The system MUST create the `context_servers` key when it is absent from settings.json on first write.
- **FR-007**: The system MUST surface a clear error if settings.json exists but cannot be parsed as valid JSON.
- **FR-008**: The system MUST NOT show Zed in the agents list when it is not installed.
- **FR-009**: Server key validation for Zed MUST enforce the pattern `^[a-z0-9][a-z0-9-]*$` (start with alphanumeric, contain only lowercase letters, digits, and hyphens) for consistency with other supported agents. Zed imposes no stricter documented restrictions, but this pattern prevents whitespace and special characters that could produce invalid or ambiguous config entries.

### Key Entities

- **ZedAdapter**: Represents Zed as a managed agent target; handles detection, read, write, and remove against settings.json.
- **MCPServerConfig (Zed mapping)**: The app's internal server model mapped to/from Zed's `context_servers` format — `command` → `path`, `args` → `args`, `envVars` → `env`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with Zed installed can add an MCP server to Zed in the same number of steps as adding it to Claude Code — no extra configuration required.
- **SC-002**: 100% of existing settings.json content is preserved after any write or remove operation performed by mcp-inator.
- **SC-003**: Drift is detected and surfaced to the user in 100% of cases where a managed entry was externally modified before an update or removal attempt.
- **SC-004**: Zed appears in the agent list within one app launch after Zed is installed — no user action required beyond restarting mcp-inator.

## Assumptions

- Zed's settings.json path on macOS is `~/.config/zed/settings.json`. Custom XDG base directory overrides are out of scope.
- Zed's settings file uses standard JSON. If a user has saved JSONC (JSON with comments), mcp-inator will fail to parse it and surface an error — comment stripping is out of scope.
- The `context_servers` format (`command.path`, `command.args`, `env`) reflects the current Zed MCP specification. Format changes in future Zed versions would require an adapter update.
- Server entries managed by mcp-inator for Zed are independent of entries managed for other agents — no cross-agent deduplication is in scope.
- Only macOS paths are in scope; Windows and Linux are excluded, consistent with the rest of the app.
- The existing AgentAdapter protocol and JSONAdapterHelper infrastructure used by ClaudeCodeAdapter, CursorAdapter, etc. will be reused.
