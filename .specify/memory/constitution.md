<!--
SYNC IMPACT REPORT
==================
Version change:    template (unversioned) → 1.0.0
Bump rationale:    Initial ratification — all placeholder tokens replaced with concrete
                   project-specific content. MAJOR bump per convention for first stable version.

Modified principles (old → new):
  [PRINCIPLE_1_NAME] → I. Native macOS Experience
  [PRINCIPLE_2_NAME] → II. Single Source of Truth
  [PRINCIPLE_3_NAME] → III. Non-Destructive Configuration
  [PRINCIPLE_4_NAME] → IV. Config Portability
  [PRINCIPLE_5_NAME] → V. Simplicity & Discoverability

Added sections:
  - Supported Integrations (replaces generic [SECTION_2_NAME])
  - Quality & Release Standards (replaces generic [SECTION_3_NAME])

Removed sections:
  None

Templates checked:
  ✅ .specify/templates/plan-template.md — generic; no mcp-inator-specific refs to update
  ✅ .specify/templates/spec-template.md — generic; no mcp-inator-specific refs to update
  ✅ .specify/templates/tasks-template.md — generic; no mcp-inator-specific refs to update
  ✅ .specify/templates/constitution-template.md — source template; no changes needed

Deferred TODOs:
  None — all fields resolved from project context.
-->

# mcp-inator Constitution

## Core Principles

### I. Native macOS Experience

mcp-inator MUST be a first-class macOS citizen: a menubar/status-bar app built with
SwiftUI, following Apple Human Interface Guidelines. The app MUST feel native — not
a web wrapper or cross-platform port. Menubar placement, system tray integration,
native controls, and macOS conventions (dark mode, accessibility, keyboard shortcuts)
are non-negotiable. Auto-update via Sparkle or equivalent native mechanism is required.

**Rationale**: Users choose a native app for reliability and polish. A menubar tool that
feels out of place erodes trust and adoption.

### II. Single Source of Truth

mcp-inator is the authoritative store for all MCP server configurations. Config data
MUST be written once into mcp-inator and MUST NOT need to be re-entered when applying
to additional AI agents. The local configuration database is the canonical record;
individual AI tool config files are derived outputs.

**Rationale**: The core problem this app solves is configuration duplication. Any design
that requires users to re-enter data in multiple places defeats the purpose.

### III. Non-Destructive Configuration

Disabling an MCP server for a specific agent MUST remove it from that agent's config
file without deleting the record from mcp-inator's store. Re-enabling MUST re-apply the
stored config without prompting the user for credentials or settings again.
Destructive operations (permanent deletion) MUST require explicit user confirmation.

**Rationale**: "Disable" means "hide from this agent temporarily." The user's intent is
to stop using it with one tool, not to forget it exists. Data loss erodes trust.

### IV. Config Portability

A configuration defined for one agent MUST be applicable to any other supported agent
with a single action. Adding support for a new agent MUST not require users to re-enter
existing configs — applying existing configs to the new agent MUST be a bulk operation.
Agent-specific config file formats are encapsulated behind adapters; the internal model
is agent-agnostic.

**Rationale**: Supporting multiple agents is the key differentiator. Each new agent should
deliver immediate value by inheriting the user's existing config library.

### V. Simplicity & Discoverability

mcp-inator MUST minimize friction for new users. A pre-defined catalog of popular MCP
servers (with pre-filled defaults) MUST be available to reduce setup time. The UI MUST
surface the most common actions without requiring users to discover settings menus.
Complexity is added only when user research or user requests justify it — no speculative
features.

**Rationale**: The target user is a developer or power user who wants quick setup, not a
configuration management expert. Friction at first use → abandonment.

## Supported Integrations

The initial supported agents are:

- **Claude** (Claude Code CLI, claude.ai desktop) — config at `~/.claude/` or platform equivalent
- **Gemini** (Gemini CLI) — config at platform-specific location
- **Codex** (OpenAI Codex CLI) — config at platform-specific location

New agent support MUST be implemented as an adapter conforming to the `AgentAdapter`
protocol/interface. Each adapter is responsible for reading and writing that agent's
config format. Adding a new adapter MUST NOT require changes to core config storage.

Third-party MCP catalog integrations (pre-defined server configs) MAY be added in future
versions. All catalog data MUST be versioned and auditable.

## Quality & Release Standards

- The app MUST be code-signed and notarized for macOS Gatekeeper compatibility.
- Auto-update MUST be implemented (Sparkle framework or equivalent) and MUST check for
  updates without requiring manual intervention.
- All config read/write operations MUST be tested with unit tests. Agent adapter
  conformance MUST be covered by integration tests using fixture config files.
- UI testing MUST cover the primary happy path (add config → apply to agent → disable →
  re-enable).
- Releases follow semantic versioning: MAJOR for breaking config schema changes,
  MINOR for new agent support or catalog additions, PATCH for bug fixes and polish.
- Config schema migrations MUST be handled automatically on app update; users MUST
  NOT be required to manually migrate data.

## Governance

This constitution supersedes all other guidance documents when conflicts arise.
Amendments require: (1) a written description of the change and rationale,
(2) a version bump per the semantic versioning rules above, (3) an updated
Sync Impact Report comment in this file, and (4) a review of all dependent templates
for consistency. Compliance is verified at the start of each feature plan (`/speckit-plan`
Constitution Check gate). Complexity violations MUST be documented in the plan's
Complexity Tracking table with explicit justification.

**Version**: 1.0.0 | **Ratified**: 2026-05-25 | **Last Amended**: 2026-05-25
