# Feature Specification: Cursor Agent Support

**Feature Branch**: `012-cursor-agent-support`

**Created**: 2026-05-31

**Status**: Draft

## Background

Cursor IDE and its CLI share a single MCP configuration file at `~/.cursor/mcp.json`.
The JSON format is identical to Claude Desktop's `claude_desktop_config.json`
(`{ "mcpServers": { ... } }`). A single `CursorAdapter` covers both the GUI app
and the CLI — no separate adapter is needed.

Cursor also supports project-scoped MCP config at `.cursor/mcp.json` inside each
repo, but that is out of scope for this feature (per-project configs are not part
of the current architecture).

---

## User Scenarios & Testing

### User Story 1 — Cursor appears in Agents after discovery (Priority: P1)

A user has Cursor installed. When they open mcp-inator, Cursor appears in the
Agents panel with its availability status, just like Claude Desktop or Gemini CLI.

**Why this priority**: Without discovery there is nothing else to do; this is the
foundation every other story depends on.

**Independent Test**: Install Cursor (or create `~/.cursor/` directory). Open
mcp-inator. Cursor should appear in the Agents list with the correct icon and
config path shown.

**Acceptance Scenarios**:

1. **Given** `~/.cursor/mcp.json` exists, **When** mcp-inator discovers agents,
   **Then** a Cursor agent record appears in the Agents panel marked as available.

2. **Given** `~/.cursor/` directory exists but `mcp.json` does not,
   **When** mcp-inator discovers agents,
   **Then** Cursor appears in the Agents panel (available = true, empty config).

3. **Given** neither `~/.cursor/mcp.json` nor `~/.cursor/` exists,
   **When** mcp-inator discovers agents,
   **Then** Cursor does NOT appear in the Agents panel.

---

### User Story 2 — Enable / disable library servers for Cursor (Priority: P1)

A user wants to push their mcp-inator library entries to Cursor (or remove them).
They toggle a server on or off in the Cursor agent view, just like they do for
Claude Desktop.

**Why this priority**: Enabling servers is the core value of the app; Cursor
should behave identically to every other file-based adapter.

**Independent Test**: Enable a library server for Cursor. Inspect
`~/.cursor/mcp.json` — the server entry should be present. Disable it — the entry
should be removed.

**Acceptance Scenarios**:

1. **Given** a server in the library, **When** the user enables it for Cursor,
   **Then** `~/.cursor/mcp.json` is updated with the correct `mcpServers` entry,
   and mcp-inator creates the file if it did not already exist.

2. **Given** a server enabled for Cursor, **When** the user disables it,
   **Then** the entry is removed from `~/.cursor/mcp.json`.

3. **Given** `~/.cursor/mcp.json` was edited externally since the last write,
   **When** the user tries to change a server's state,
   **Then** drift detection fires and the change is blocked with an appropriate
   error (same behaviour as other adapters).

---

### User Story 3 — Import existing Cursor MCP servers into the library (Priority: P2)

A user already has MCP servers configured in `~/.cursor/mcp.json`. They want to
bring those into the mcp-inator library so they can manage them from one place and
push them to other agents.

**Why this priority**: Import is a quality-of-life feature for existing Cursor
users; the app is still functional without it.

**Independent Test**: Pre-populate `~/.cursor/mcp.json` with one or two server
entries. Use the Import menu inside the Cursor agent view. The servers should
appear as importable items and be added to the library on confirm.

**Acceptance Scenarios**:

1. **Given** `~/.cursor/mcp.json` contains server entries not yet in the library,
   **When** the user triggers Import from Cursor,
   **Then** those servers appear in the ImportReviewView as new/importable entries.

2. **Given** a server in `~/.cursor/mcp.json` already exists in the library
   (matching serverKey),
   **When** the user triggers Import,
   **Then** it is shown as an exact match or conflict, not as a new entry.

3. **Given** `~/.cursor/mcp.json` is empty or has no `mcpServers` key,
   **When** the user triggers Import,
   **Then** the import sheet shows an empty / "nothing to import" state.

---

### Edge Cases

- `~/.cursor/mcp.json` contains a server key with underscores or other characters
  that pass Cursor's own validation but fail mcp-inator's key validation rules —
  treat the same as any other adapter: surface a validation warning during import.
- User has both global (`~/.cursor/mcp.json`) and project-scoped
  (`.cursor/mcp.json`) configs — mcp-inator only manages the global file.
- Cursor is not installed (no `/Applications/Cursor.app`) but the config file
  exists — still discover and manage it (same pattern as other adapters: presence
  of the config directory/file is sufficient).

---

## Requirements

### Functional Requirements

- **FR-001**: App MUST discover Cursor as an agent if `~/.cursor/mcp.json` exists
  OR if the `~/.cursor/` directory exists.
- **FR-002**: App MUST read MCP server entries from `~/.cursor/mcp.json` using the
  standard `mcpServers` JSON key.
- **FR-003**: App MUST write enabled MCP server entries to `~/.cursor/mcp.json`,
  creating the file if absent (preserving any non-`mcpServers` keys that may exist).
- **FR-004**: App MUST remove disabled MCP server entries from `~/.cursor/mcp.json`
  with drift detection identical to other file-based adapters.
- **FR-005**: App MUST expose Cursor in the Import flow so users can import
  existing servers from `~/.cursor/mcp.json` into the library.
- **FR-006**: App MUST display Cursor with a recognisable icon in the Agents panel.
- **FR-007**: `AgentType` enum MUST gain a `.cursor` case with raw value
  `"cursor"` and display name `"Cursor"`.
- **FR-008**: `AgentType.defaultConfigPath` MUST return `~/.cursor/mcp.json` for
  `.cursor`.
- **FR-009**: `CursorAdapter` MUST be registered in all `allAdapters` arrays
  (currently `mcp_inatorApp.swift` and `MenuBarView.swift`).
- **FR-010**: Project-scoped `.cursor/mcp.json` files are OUT OF SCOPE.
- **FR-011**: Cursor CLI shares the same config file as Cursor IDE; a single
  adapter covers both — no separate `CursorCLIAdapter`.

### Key Entities

- **CursorAdapter** (`AgentAdapter`): reads/writes `~/.cursor/mcp.json` via
  `JSONAdapterHelper`; `isAppManaged = false`; `validateServerKey` uses the same
  `^[a-z0-9][a-z0-9-]*$` rule as `ClaudeDesktopAdapter`.
- **AgentType.cursor**: new enum case; `rawValue = "cursor"`;
  `displayName = "Cursor"`; `isAppManaged = false`.
- **AgentIcon** (UI): new `case .cursor` branch returning a Cursor icon asset or
  system image fallback.

---

## Success Criteria

- **SC-001**: Cursor appears in the Agents panel when `~/.cursor/` exists, with
  correct icon, display name, and config path.
- **SC-002**: Enabling a library server for Cursor writes the correct JSON entry
  to `~/.cursor/mcp.json`; disabling removes it — verified by reading the file.
- **SC-003**: Importing from Cursor correctly categorises existing entries
  (new / exactMatch / conflict) in `ImportReviewView`.
- **SC-004**: All existing adapter tests continue to pass; new
  `CursorAdapterTests` cover read, write, remove, and `isInstalled` paths.
- **SC-005**: `make lint` passes with zero violations after the change.

---

## Assumptions

- Cursor's `mcpServers` JSON format stays consistent with the current documented
  format (identical to Claude Desktop); if Cursor changes its schema a migration
  will be needed.
- The global config (`~/.cursor/mcp.json`) is the right scope for this app; no
  per-project config management.
- An icon asset for Cursor will be sourced or approximated (e.g. a simple
  monogram image or SF Symbol fallback) — final asset TBD at implementation time.
- A new database migration is NOT required: `AgentType` is stored as a raw string
  in SQLite; adding `.cursor = "cursor"` is backward-compatible with existing
  rows and the existing unknown-type fallback (`?? .claudeCode`). The fallback
  should be reviewed and possibly changed to an optional or separate unknown case,
  but that is out of scope here.
