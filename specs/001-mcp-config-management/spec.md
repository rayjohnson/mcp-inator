# Feature Specification: MCP Server Configuration Management

**Feature Branch**: `001-mcp-config-management`

**Created**: 2026-05-25

**Status**: Draft

**Input**: User description: "MCP server configuration management — add MCP server configs once
in mcp-inator, then enable or disable per AI agent (Claude Code CLI, Claude Desktop, Gemini
CLI, Codex CLI) without re-entering config details. Applying existing configs to new agents
is a bulk operation. Handles non-standard paths, permission errors, agent restart
notifications, and agent-specific JSON format differences."

## Clarifications

### Session 2026-05-25

- Q: Should env var values support literal strings, env var references (e.g. `${GITHUB_TOKEN}`), or both? → A: Both — user enters either a literal value or an env var reference per field; mcp-inator stores and writes exactly what the user entered. Literal values are masked in the UI; env var references are shown plainly.
- Q: Should writes to agent config files be atomic to prevent file corruption on crash? → A: Yes — write to a temp file in the same directory, then atomically rename over the target. The file is always either fully old or fully new, never partial.
- Q: If mcp-inator's internal store is deleted or corrupted, what should happen? → A: Graceful empty state — start fresh, inform the user the library was not found, and immediately offer to re-import from detected agent config files. Cloud backup/sync is a future spec.
- Q: What transformation rule should auto-populate the server key from the display name? → A: Default is lowercase, spaces→hyphens, strip non-alphanumeric-and-hyphen characters (e.g. "GitHub MCP" → `github-mcp`). Research during planning may adjust this per agent if their config formats have different constraints.
- Q: What should the user see when the config library is empty or no agents are found at first-run? → A: Actionable empty state — show a clear call-to-action ("Add your first MCP server") when the library is empty; show a secondary message explaining how to configure an agent path manually when no agents were found during discovery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add MCP Server Config (Priority: P1)

A developer discovers a new MCP server (e.g., GitHub, Obsidian) and wants to start using it
across their AI tools. They open mcp-inator from the macOS menubar, add the server config once
— giving it a display name, a server key (auto-populated, editable), command/URL, any
environment variables, and optional arguments — and the config is stored in mcp-inator's
library ready to be applied to agents.

**Why this priority**: Entry point to all other functionality. Without a stored config library,
nothing else is possible.

**Independent Test**: Can be fully tested by launching mcp-inator, adding a new MCP server
entry with required fields, and verifying the entry appears in the config library — entirely
without any agent integration.

**Acceptance Scenarios**:

1. **Given** no configs exist, **When** the user taps "Add Server" and fills in the display
   name and command, **Then** the server key is auto-populated from the display name and the
   new entry appears in the config library list.
2. **Given** the user edits the auto-populated server key before saving, **When** they save,
   **Then** the custom server key is stored and used as the key in agent config files.
3. **Given** a config already exists, **When** the user adds a second config with a different
   name, **Then** both entries are listed in the config library.
4. **Given** the user submits an incomplete form (missing required fields), **When** they tap
   save, **Then** validation errors are shown inline and no record is created.
5. **Given** a config exists, **When** the user edits it and saves, **Then** the updated values
   are reflected in the library.
6. **Given** a config exists, **When** the user deletes it after confirming the prompt, **Then**
   it is permanently removed from the library and from any agent config files where it was
   enabled.

---

### User Story 2 - Apply Config to an AI Agent (Priority: P1)

A developer has configs stored in mcp-inator and wants Claude to use a specific MCP server.
They open the agent view for Claude, enable the desired config(s). mcp-inator writes the
correct entries to Claude's config file using the config's server key as the JSON key. If
the agent requires a restart to pick up the change, mcp-inator immediately tells the user.
The developer can later disable a config for Claude — which removes it from Claude's config
file — without losing the record in mcp-inator.

**Why this priority**: Core value delivery — this is what makes mcp-inator useful day-to-day.
P1 alongside Story 1 because the two stories together form the MVP.

**Independent Test**: Can be fully tested by adding one config (Story 1 prerequisite), enabling
it for Claude, inspecting Claude's config file to verify the entry was written using the
correct server key, then disabling it and verifying the entry was removed while the config
still exists in mcp-inator.

**Acceptance Scenarios**:

1. **Given** a config exists in the library, **When** the user enables it for Claude, **Then**
   the correct entry is written to Claude's MCP config file using the config's server key.
2. **Given** a config is enabled for Claude Desktop (which requires restart), **When** the
   write completes successfully, **Then** mcp-inator displays a clear notification that
   Claude Desktop needs to be restarted for the change to take effect.
3. **Given** a config is enabled for Claude, **When** the user disables it, **Then** the entry
   is removed from Claude's config file and the config remains in the mcp-inator library.
4. **Given** a config was previously disabled for Claude, **When** the user re-enables it,
   **Then** the entry is re-written to Claude's config file without the user re-entering any
   data.
5. **Given** a config is enabled for Claude, **When** the user views the agent list, **Then**
   the config is clearly marked as active for that agent.
6. **Given** Claude's config file does not exist yet, **When** the user enables a config,
   **Then** mcp-inator creates the file (or the relevant section) with the correct entry.

---

### User Story 3 - Bulk Apply Configs to a New Agent (Priority: P2)

A developer who has been using mcp-inator with Claude decides to start using Gemini CLI.
They open the "Agents" view, add Gemini as a target, select "Apply all" (or cherry-pick),
and mcp-inator writes the chosen configs to Gemini's config file in one step — without the
developer re-entering any server details. If Gemini requires a restart, mcp-inator says so.

**Why this priority**: Major differentiator — unlocks the cross-agent value proposition.
Secondary to P1 stories because it depends on having configs and at least one working agent
adapter.

**Independent Test**: Can be fully tested by having configs enabled for Claude (P1 stories
complete), adding Gemini as a new agent, bulk-applying all configs, and verifying Gemini's
config file contains the correct entries with correct server keys.

**Acceptance Scenarios**:

1. **Given** multiple configs exist in the library, **When** the user bulk-applies them to a
   new agent, **Then** all selected configs are written to that agent's config file using
   each config's server key.
2. **Given** an agent has no previously applied configs, **When** the user applies a subset,
   **Then** only the selected configs appear in the agent's config file.
3. **Given** a config is applied to Agent A, **When** the user adds Agent B and bulk-applies,
   **Then** Agent A's config is unchanged and Agent B receives the applied configs.
4. **Given** a bulk apply completes for an agent that requires restart, **When** the operation
   finishes, **Then** mcp-inator shows a single consolidated restart notification for that
   agent — not one per config.

---

### User Story 4 - View Config Status Across Agents (Priority: P3)

A developer wants to see at a glance which configs are active for which agents. The main
mcp-inator view shows each stored config alongside its enabled/disabled state per agent,
so the developer can quickly audit and spot missing coverage. Agents that are unavailable
(bad path or permissions) are visually distinguished from agents where configs are simply
disabled.

**Why this priority**: Enhances visibility and trust but is not needed for core functionality.

**Independent Test**: With configs enabled for multiple agents, opening the status view shows
the correct enabled/disabled/unavailable state per agent per config.

**Acceptance Scenarios**:

1. **Given** Config A is enabled for Claude and disabled for Gemini, **When** the user opens
   the status view, **Then** Config A shows "enabled" under Claude and "disabled" under Gemini.
2. **Given** a new config is added but not yet applied to any agent, **When** the user views
   the status, **Then** all agents show "disabled" for that config.
3. **Given** an agent's config file is inaccessible, **When** the user views the status,
   **Then** that agent shows a distinct "unavailable" state (not "disabled") with a short
   diagnostic hint explaining the cause.

---

### User Story 5 - First-Run Agent Discovery (Priority: P1)

When mcp-inator is launched for the first time, it automatically scans the Mac for all
supported AI tools. It shows which were found. For each tool that has existing MCP servers
configured, mcp-inator offers to import them into the library. The user decides per-tool —
nothing is imported or modified without explicit approval.

On subsequent relaunches, if mcp-inator detects a supported tool that wasn't present before
(e.g., the user just installed Codex CLI), it triggers the same discovery-and-import offer
for that tool only. mcp-inator NEVER automatically applies configs to a newly discovered
tool — that is always a deliberate user action.

**Why this priority**: The first-run moment is the highest-churn moment. Proactive discovery
immediately demonstrates value and eliminates the blank-slate problem.

**Independent Test**: Can be fully tested by pre-installing one supported agent with existing
MCP entries, launching mcp-inator fresh, and verifying the discovery screen appears with the
correct agent listed and import offered.

**Acceptance Scenarios**:

1. **Given** mcp-inator is launched for the first time, **When** launch completes, **Then**
   the app scans for all supported agents and presents a discovery screen showing which
   were found.
2. **Given** the discovery screen is shown and Agent A has existing MCP entries, **When**
   the user chooses to import from Agent A, **Then** the per-entry import flow (US7) is
   launched for that agent — showing new entries, exact matches, and diffs for conflicts.
   Nothing is imported without an explicit per-entry decision.
3. **Given** the discovery screen is shown, **When** the user declines import for an agent,
   **Then** that agent's config file is not modified and no entries are imported from it.
4. **Given** mcp-inator has previously run and Codex CLI was not installed, **When**
   mcp-inator is relaunched and Codex CLI is now detected, **Then** mcp-inator presents the
   discovery-and-import offer for Codex CLI only — already-known agents are not re-scanned.
5. **Given** a newly discovered agent has no existing MCP entries, **When** it appears in
   the discovery screen, **Then** it is listed as "no existing configs" and added to the
   agent list without an import prompt.
6. **Given** mcp-inator discovers a new agent, **When** the user completes or dismisses the
   discovery flow, **Then** no configs are applied to the new agent automatically.
7. **Given** first-run scan finds no supported agents at all, **When** the discovery screen
   is shown, **Then** it displays a clear message that no supported agents were detected and
   explains how to configure an agent path manually (linking to the path override flow).
8. **Given** first-run discovery completes and the user has declined all imports, **When**
   the user arrives at the main view, **Then** an actionable empty state is shown with a
   prominent "Add your first MCP server" call-to-action.

---

### User Story 6 - Propagate Config Edits to Enabled Agents (Priority: P2)

A developer realizes a config's token has changed. They edit the config in mcp-inator and
save. Because that config is currently enabled in Claude Desktop and Gemini CLI, mcp-inator
immediately offers to apply the updated values to those agents. Before writing, it reads the
current on-disk state of each affected entry and shows the user exactly what will change.
The developer confirms and both agent config files are updated. Agents where the config is
disabled are unaffected — they will receive the new values the next time the config is
enabled for them.

**Why this priority**: Without this, editing a config requires the user to manually disable
and re-enable it for every agent — exactly the friction mcp-inator is meant to eliminate.

**Independent Test**: Can be fully tested by enabling a config for two agents, editing the
config, accepting the propagation offer, and verifying both agents' config files reflect the
updated values.

**Acceptance Scenarios**:

1. **Given** Config A is enabled for Claude and Gemini, **When** the user edits Config A and
   saves, **Then** mcp-inator presents a prompt offering to immediately apply the changes to
   Claude and Gemini, showing the before/after diff for each agent.
2. **Given** the propagation prompt is shown, **When** the user accepts, **Then** both
   Claude's and Gemini's config files are updated. If either agent requires a restart,
   a consolidated restart notification is shown.
3. **Given** the propagation prompt is shown, **When** the user declines, **Then** the
   mcp-inator library is updated but neither agent's config file is changed. No special
   state is tracked. The next time the user initiates any operation that would write to
   those agents, mcp-inator reads the current file state and surfaces any discrepancies
   before proceeding.
4. **Given** Config A is enabled for Claude but disabled for Gemini, **When** the user edits
   and saves, **Then** the propagation offer is shown for Claude only. Gemini is not
   mentioned — it will receive the new values when next enabled.
5. **Given** Config A is not enabled for any agent, **When** the user edits and saves, **Then**
   no propagation prompt is shown.

---

### User Story 7 - Import Configs from an Agent (Priority: P2)

At any point after first-run, a developer wants to pull in MCP server entries that already
exist in an agent's config file — perhaps they were added manually, or by another tool.
They trigger "Import from agent" for a specific agent. mcp-inator reads that agent's config
file and presents a per-entry review screen:

- **New entries** (key not in the mcp-inator library): shown with full details — user can
  import or skip each one.
- **Exact matches** (key exists in library, values identical): shown as "already in library"
  — no action needed.
- **Conflicts** (key exists in library, values differ): shown as a side-by-side diff — user
  chooses "keep library version", "use agent version", or "skip".

Nothing is imported or overwritten without an explicit per-entry decision. This is the same
per-entry diff flow used during first-run discovery (US5).

**Why this priority**: Builds on the first-run import UI (which must be built anyway).
Allows users to pick up manually-added or externally-managed entries at any time, not
just at first launch.

**Independent Test**: Can be fully tested by pre-populating an agent's config file with
three entries (one new, one matching, one conflicting vs. the library), triggering import,
and verifying the review screen shows all three categories correctly and that the library
reflects only the user's confirmed choices.

**Acceptance Scenarios**:

1. **Given** an agent's config file has an entry whose key is not in the library, **When**
   the user reviews it in the import screen, **Then** it is shown as "new" and the user
   can import or skip it.
2. **Given** an agent's config file has an entry whose key and values exactly match a
   library entry, **When** the user views the import screen, **Then** it is shown as
   "already in library" with no action required.
3. **Given** an agent's config file has an entry whose key matches a library entry but
   values differ, **When** the user views the import screen, **Then** a side-by-side diff
   is shown and the user must choose "keep library version", "use agent version", or "skip".
4. **Given** the user completes the import review, **When** they confirm, **Then** only
   the entries they approved are added or updated in the library — all others are unchanged.
5. **Given** the import screen is shown, **When** the user cancels entirely, **Then** the
   library and the agent's config file are both unchanged.

---

### Edge Cases

- What happens when an AI agent's config file is in a non-standard location (user moved it,
  symlinked it, or installed the agent in a custom path)?
- What happens when mcp-inator cannot write to an agent's config file due to filesystem
  permissions — how is this distinguished from a "disabled" state in the UI?
- What happens when the config file is locked by another process at the moment mcp-inator
  tries to write? (Atomic write via temp-rename mitigates corruption; locking may still
  cause the rename to fail — FR-012 error handling applies.)
- What happens when two configs have the same server key?
- What happens when mcp-inator is updated and the internal config schema changes — are
  existing stored configs migrated automatically?
- What happens when a user deletes a config that is currently enabled for one or more agents
  and one of those agents is currently unavailable?
- What happens when the first-run scan is interrupted (e.g., user closes the app mid-scan)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow users to create a new MCP server config entry with:
  display name (human-readable, used only inside mcp-inator), server key (auto-populated
  from display name by lowercasing, replacing spaces with hyphens, and stripping all
  non-alphanumeric-and-hyphen characters — e.g. "GitHub MCP" → `github-mcp`; always
  user-editable before saving; used as the JSON key in agent config files),
  command/URL, optional environment variables (key-value pairs where each value is either
  a literal string or an env var reference such as `${GITHUB_TOKEN}`; each literal value
  is flaggable as sensitive), and optional arguments.
- **FR-002**: The system MUST persist all config entries in a local store on the Mac that
  survives app restarts.
- **FR-003**: The system MUST allow users to edit any stored config entry.
- **FR-004**: The system MUST allow users to delete a stored config entry after explicit
  confirmation; deletion MUST remove the entry from all reachable agent config files where
  it is currently enabled.
- **FR-005**: The system MUST allow users to enable a stored config for a specific supported
  agent, which writes the entry to that agent's config file using the config's server key.
- **FR-006**: The system MUST allow users to disable a stored config for a specific agent,
  which removes the entry from that agent's config file without deleting the record.
- **FR-007**: The system MUST allow re-enabling a previously disabled config for any agent
  without requiring the user to re-enter config data.
- **FR-008**: The system MUST support bulk-applying a selection of configs to an agent in a
  single operation.
- **FR-009**: The system MUST display the enabled/disabled/unavailable status of each config
  per supported agent.
- **FR-010**: The system MUST support Claude Code CLI, Claude Desktop, Gemini CLI, and Codex
  CLI as target agents at launch. The agent adapter architecture MUST allow new agents to be
  added without modifying core config storage logic.
- **FR-011**: The system MUST handle agent config file creation if the file or relevant
  section does not already exist.
- **FR-012**: When writing to an agent's config file fails, the system MUST surface a clear,
  user-readable explanation of the specific cause (e.g., "Claude's config file is read-only
  — check Finder permissions at ~/path/to/file") and MUST NOT display a generic failure
  message or imply the operation succeeded.
- **FR-013**: When an agent's config file path cannot be found at the expected default
  location, the system MUST prompt the user to provide the correct path and persist that
  override. The message MUST explain the default path was not found — not that the tool
  failed.
- **FR-014**: An agent with an unresolvable config path or insufficient write permissions
  MUST be shown in a distinct "unavailable" state — visually differentiated from agents
  that are reachable but have configs disabled. The user MUST be prevented from attempting
  enable/disable operations on an unavailable agent until the issue is resolved.
- **FR-015**: Each supported agent MUST have a dedicated format adapter responsible for
  reading and writing that agent's specific config file structure. The canonical mcp-inator
  config model MUST be translated by the adapter — agent-specific format details MUST NOT
  leak into core storage logic.
- **FR-016**: Env var values that are literal strings and flagged as sensitive MUST be
  masked by default in all UI views (displayed as `••••`) with a per-field "reveal" toggle.
  Env var references (e.g. `${GITHUB_TOKEN}`) are not sensitive by definition and MUST be
  shown plainly. Masked literal values MUST NOT appear in any view without deliberate user
  action.
- **FR-017**: When the user saves an edit to a config that is currently enabled for one or
  more agents, the system MUST offer to immediately propagate the updated values to those
  agents before the user leaves the edit view. Agents where the config is disabled MUST NOT
  be included in the propagation offer.
- **FR-018**: On first launch, the system MUST automatically scan for all supported agents
  and present a discovery screen. For each agent found with existing MCP entries, the system
  MUST offer to import them. No configs may be imported or applied without explicit user
  approval per agent.
- **FR-019**: On subsequent launches, the system MUST check for supported agents not
  previously detected. If a new agent is found, the system MUST trigger the discovery-and-
  import offer for that agent only. Already-known agents MUST NOT be re-scanned at launch.
- **FR-020**: mcp-inator MUST never automatically apply configs to any agent. All config
  application MUST be initiated by an explicit user action.
- **FR-021**: The system MUST allow users to override the config file path for any supported
  agent and persist that override. An agent in "unavailable" state due to a missing default
  path MUST offer the path-override prompt as its primary resolution action.
- **FR-022**: After any successful write to an agent's config file, the system MUST display
  a clear notification telling the user to restart that agent for the changes to take
  effect. For bulk operations, one consolidated notification per agent MUST be shown —
  not one per config. The default assumption is that all agents require a restart; this
  may be refined per-adapter once restart behavior is verified during research.
- **FR-023**: Before executing any write to an agent's config file (enable, disable,
  bulk-apply, or propagate-edit), the system MUST read the current on-disk state of the
  affected entries. If any entry's current on-disk state differs from what mcp-inator
  expects to find (entry exists with unexpected values, or an entry being removed has been
  modified), the system MUST present the discrepancy to the user and require explicit
  confirmation before writing. This applies even when the write was user-initiated moments
  earlier.
- **FR-024**: When enabling a config for an agent and the agent's config file already
  contains an entry with the same server key that was not written by mcp-inator, the system
  MUST detect the conflict, display both the existing on-disk value and the mcp-inator
  value, and require the user to choose which to use. The system MUST NOT silently
  overwrite an entry it did not create.
- **FR-025**: The system MUST provide an "Import from agent" action for any agent in the
  agent list, triggering the per-entry import flow: new entries (import or skip), exact
  matches (shown as already in library), and conflicts (side-by-side diff with user
  choice). Nothing is imported without an explicit per-entry decision.
- **FR-026**: The system MUST automatically migrate stored config data to the current
  schema when the app is updated. Users MUST NOT be required to manually migrate data
  between versions.
- **FR-027**: All writes to agent config files MUST be atomic: the system MUST write to
  a temporary file in the same directory, then rename it over the target. The target file
  MUST remain in a valid state if the app crashes or is killed mid-write.
- **FR-028**: If mcp-inator's internal data store is missing or unreadable at launch, the
  system MUST start in a clean empty state (not crash or refuse to launch), MUST inform
  the user that their previous library data was not found, and MUST immediately offer to
  re-import from any currently detected agent config files.
- **FR-029**: When the config library is empty (no entries), the main view MUST show an
  actionable empty state with a prominent "Add your first MCP server" call-to-action.
  When first-run discovery finds no supported agents, the discovery screen MUST display a
  clear explanation and direct the user to the path override flow (FR-021) to configure
  an agent manually. Generic blank views with no guidance are not acceptable.

### Key Entities

- **MCP Server Config**: The stored definition of an MCP server — display name (shown in
  mcp-inator UI), server key (used as the JSON key in agent config files, auto-populated
  from display name, user-editable), command/URL, environment variables (key-value pairs
  where each value is either a literal string optionally flagged as sensitive, or an env
  var reference such as `${GITHUB_TOKEN}` which is always shown plainly), arguments
  (list), description (optional). This is the canonical record; it exists independently
  of any agent.
- **Agent**: A supported AI tool (Claude Code CLI, Claude Desktop, Gemini CLI, Codex CLI)
  with a known default config file path and format. Whether the agent requires a restart
  after config changes is an agent-specific property. Agents are extensible — new agents
  can be added by implementing an adapter without changing existing logic.
- **Agent Adapter**: Encapsulates all knowledge of a specific agent's config file format,
  location, and runtime behavior (e.g., requires restart). Responsible for reading, writing,
  and translating between the agent's on-disk format and mcp-inator's canonical model.
  One adapter per agent.
- **Config-Agent Assignment**: The relationship between a config and an agent. States:
  *enabled* (entry present in agent's config file),
  *disabled* (absent from file, retained in store),
  *unavailable* (agent config file cannot be accessed).
  Note: mcp-inator does not track whether the on-disk value matches its stored value as
  a persistent state — discrepancies are surfaced reactively at write time via the
  pre-flight diff check.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can add a new MCP server config from scratch in under 60 seconds.
- **SC-002**: Enabling a stored config for an agent takes a single action and completes
  within 2 seconds.
- **SC-003**: A user can apply all stored configs to a new agent in a single bulk operation
  without re-entering any data.
- **SC-004**: Disabling a config for an agent and re-enabling it requires zero re-entry of
  config data.
- **SC-005**: 100% of stored configs survive an app restart without data loss.
- **SC-006**: Adding a config in mcp-inator and enabling it for an agent results in a
  verifiably correct entry in that agent's config file, using the correct server key,
  readable by the agent.
- **SC-007**: When an agent's config file is inaccessible, the user receives a specific
  actionable explanation within 2 seconds of attempting any operation on that agent.
- **SC-008**: Sensitive environment variable values are never visible in the UI without an
  explicit per-field reveal action by the user — including in list views and tooltips.
- **SC-009**: When the user saves a config edit that affects enabled agents, the propagation
  offer is presented before the user leaves the edit view.
- **SC-010**: First-run agent discovery completes and presents results within 5 seconds of
  initial launch on a standard Mac with supported agents installed.

## Assumptions

- macOS is the only supported platform for this feature; no iOS, Windows, or Linux support.
- Default config file locations for Claude Code CLI, Claude Desktop, Gemini CLI, and Codex
  CLI are researchable and stable enough to ship as defaults, with user-configurable path
  overrides for non-standard installs.
- All supported agents are assumed to require a restart to pick up config file changes.
  The planning research phase MUST verify the actual restart behavior for each agent;
  agents confirmed to pick up changes without restart MAY suppress the restart
  notification in their adapter. Until verified, the notification is always shown.
- Each agent may store MCP configs in a structurally different JSON format; mcp-inator's
  canonical model is agent-agnostic and adapters handle translation in both directions.
- Sensitive field values are masked in the UI for casual protection; they are not encrypted
  beyond macOS standard file-system protections. The underlying config files written to
  agents are plaintext, consistent with how those agents store configs today.
- mcp-inator does not manage OS-level filesystem permissions; if a config file is unwritable,
  the app tells the user what to fix and waits for them to resolve it externally.
- Agent auto-discovery uses known default install paths and executable names; it does not
  perform a filesystem-wide search.
- Cloud backup, export-to-file, and cross-machine sync are out of scope for this feature
  and are planned for a dedicated future spec. A pre-defined MCP server catalog is also
  a separate future feature.
- Auto-update functionality is out of scope for this feature.
