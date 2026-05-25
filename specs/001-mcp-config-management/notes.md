# Notes & Open Questions: MCP Server Configuration Management

Items deferred from spec review. Resolved decisions recorded for traceability.

---

## Resolved Decisions

### N-001: Config display name vs. agent JSON key — RESOLVED

**Decision**: Two fields.
- **Display name** — human-readable, shown only inside mcp-inator UI.
- **Server key** — auto-populated from display name, user-editable, used as the JSON key
  in agent config files.

The exact auto-population transformation rule (how "GitHub MCP" becomes a key like
`github-mcp`) is **unknown** — see Research Item R-001 below.

---

### N-002: Drift detection timing — RESOLVED

**Decision**: Reactive, not proactive. mcp-inator reads the current on-disk state
immediately before any write operation and surfaces discrepancies at that moment (FR-023).
No background file watching. No persistent "drifted" state tracked.

---

### N-003: Deletion cascade when an agent is unavailable — DEFERRED TO PLANNING

**Decision**: Not resolved in spec. FR-004 says delete from all *reachable* agents.
Behavior for unavailable agents (warn and proceed? block? queue?) is to be decided during
planning. See Research Item R-003.

---

### N-004: "Pending" state vs. "external drift" disambiguation — RESOLVED

**Decision**: No "pending" state is tracked. When the user declines propagation, the
library is updated and no further action is taken. The next time any write to the affected
agents is attempted, FR-023 (pre-flight diff check) will surface the discrepancy naturally.

---

### N-005: Import boundary (first-run vs. manual) — RESOLVED

**Decision**: The per-entry import flow (US7) is a single shared UI component used in
both contexts:
- **First-run / new agent discovery (US5)**: triggers US7 flow per agent the user chooses
  to import from
- **Manually triggered (US7)**: user initiates "Import from agent" at any time from the
  agent list

Both use the same three-category display: new entries (import or skip), exact matches
(already in library), conflicts (side-by-side diff, user chooses).

**There is no "bulk accept all"** — this was explicitly rejected as too dangerous since
we cannot know the provenance or currency of existing configs.

---

## Research Items (resolve during /speckit-plan)

### R-001: Per-agent server key format constraints — PARTIALLY RESOLVED

**Default rule** (decided): lowercase, spaces→hyphens, strip non-alphanumeric-and-hyphen
characters. "GitHub MCP" → `github-mcp`. Always user-editable before saving.

**Still to research during planning**: Do any of the four supported agents (Claude Code
CLI, Claude Desktop, Gemini CLI, Codex CLI) impose additional constraints on MCP server
keys — e.g. length limits, disallowed leading characters, case sensitivity, or reserved
names? If so, per-adapter validation or sanitization may be needed at enable-time, and
the auto-population rule may need adjustment for specific agents.

---

### R-002: Duplicate server key behavior

**Question**: If two configs in the mcp-inator library share the same server key, and
both are enabled for the same agent, the second write silently overwrites the first in
that agent's config file. Should mcp-inator enforce uniqueness of server keys in the
library? Or only detect conflicts at enable-time (per-agent)?

**Why it matters**: This affects whether the library-level data model needs a unique
constraint on server key, or whether the conflict is only relevant at the agent level
(handled by FR-024).

**Suggested approach**: Don't enforce library-level uniqueness yet. FR-024 already
handles conflicts at enable-time. Revisit if users report confusion.

---

### R-003: Deletion cascade with unavailable agent

**Question**: A config is enabled for Agent A (reachable) and Agent B (unavailable).
The user deletes the config. Agent A's file is updated. What happens for Agent B?

**Options**:
- Warn the user, let them proceed (partial delete) or cancel
- Queue the deletion for Agent B and apply when it becomes reachable
- Block deletion until all enabled agents are reachable

**Suggested approach**: Warn and proceed with partial delete. Show clearly which agents
were updated and which were not. Mark it as a known inconsistency the user needs to
resolve (e.g., when Agent B is reachable again, the entry will still be there).

---

### R-004: Agent restart behavior

**Question**: Which supported agents require a restart to pick up MCP config file changes?
Claude Code CLI, Claude Desktop, Gemini CLI, Codex CLI — what is the verified behavior
for each?

**Current assumption**: All require restart (FR-022 notifies after every write).
Research during planning phase MAY identify exceptions that allow suppressing the
notification for specific agents.

---

## Future Spec 002: Config Drift & Reconciliation

Now that pre-flight diff checking (FR-023) is in Spec 001, Spec 002 focuses on
*proactive* drift detection — cases where the file changes but no write is pending.

### Suggested scope for Spec 002

- Background or on-open file reading to detect changes made outside mcp-inator
- A "drifted" state in the status view for entries that have changed since mcp-inator
  last wrote them
- A reconciliation flow for drifted entries: "use agent version" or "use mcp-inator
  version"
- The "untracked entry" case: a new entry appears in an agent's file that mcp-inator
  didn't write and hasn't been imported — offer import, don't silently delete

---

## Future Spec 003: Advanced Agent Management

### Suggested scope for Spec 003

- Manually register an unsupported AI tool (name, config path, compatible format
  selection)
- Remove an agent from the agent list (clears assignments, retains library entries)
- Possibly: multiple named instances of the same agent type (e.g., two Claude Desktop
  installs)

---

## Future Spec 004: Cloud Backup & Sync

User requested this be a planned future spec. Scope suggestion:
- Export library to file (JSON/portable format)
- Import library from file (restore after Mac replacement)
- Optional cloud sync (iCloud Drive, or a cloud provider) so configs survive hardware changes
- Possible: share a library between multiple Macs

---

## Explicitly Out of Scope (all specs except Spec 004)

| Item | Notes |
|------|-------|
| Cloud backup / export to file | Planned for Spec 004 |
| Cross-machine sync | Planned for Spec 004 |
| Pre-defined MCP server catalog | Separate feature; referenced in constitution |
| Background file watching | Proactive drift detection; Spec 002 |
| Keychain / encrypted storage | Sensitive fields masked in UI; underlying files are plaintext |
| Auto-update (Sparkle) | Separate feature; referenced in constitution |
