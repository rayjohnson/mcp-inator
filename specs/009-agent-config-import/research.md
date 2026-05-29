# Research: Import MCP Servers from Agent Config Files

**Feature**: 009-agent-config-import  
**Date**: 2026-05-29

## Decision 1: Import Source Discovery Strategy

**Decision**: Scan all known adapter instances directly in `ConfigLibraryView` rather than filtering `store.agents`.

**Rationale**: `store.agents` only contains agents the user has already registered through discovery. A new user with an empty agent DB would see no Import menu at all. Scanning adapters directly (calling `isInstalled()` + checking config file existence) gives a complete, registration-independent picture of what can be imported.

**Alternatives considered**:
- Filter `store.agents` (current approach) — excluded: breaks for new users who haven't registered agents
- Add a separate scan method to `ConfigStore` — excluded: unnecessary indirection; view can do this cheaply

## Decision 2: New `ImportSource` Type

**Decision**: Introduce a lightweight `ImportSource` struct (private to `ConfigLibraryView`) carrying `displayName`, `agentType`, `adapter`, `configPath`, and `isImportable`/`unavailableReason`. This replaces the `AgentRecord` currently passed through `prepareImport` and `ImportReviewView`.

**Rationale**: `AgentRecord` is a database entity requiring a registered agent. `ImportSource` is a transient, adapter-derived value with no DB dependency. Keeping it private to the import flow avoids leaking a new type into the store layer.

**Alternatives considered**:
- Reuse `AgentRecord` with a fake/nil id — excluded: semantically wrong, fragile
- Pass adapter + path as loose parameters — excluded: too many parameters threading through view hierarchy

## Decision 3: `applyImportDecisions` Agent Assignment

**Decision**: Make `agentId` optional (`Int64?`) in `ConfigStore.applyImportDecisions`. When `nil`, the method inserts/updates the `MCPServerConfig` library records but skips `setAssignmentState` — the server lands in the library without being enabled for any agent.

**Rationale**: The spec explicitly states "Importing a server does not automatically enable it for any agent." The existing call sites (`DiscoveryView` flow) pass a real `agentId` and continue to auto-enable as before. The new import flow passes `nil`.

**Alternatives considered**:
- New overload without `agentId` — acceptable but adds a second method with near-identical body
- Always auto-enable for the source agent (requires registering it first) — excluded: contradicts spec and adds onboarding dependency

## Decision 4: Disabled Menu Item for Gemini Desktop

**Decision**: Render disabled import sources as `Button(...).disabled(true)` inside the existing `Menu`, with a `.help()` tooltip explaining why import is unavailable. No custom menu view needed.

**Rationale**: SwiftUI's `Button` with `.disabled(true)` inside `Menu` renders greyed-out and non-interactive on macOS — exactly the visual treatment needed. The `.help()` modifier provides the tooltip on hover with no extra code.

**Alternatives considered**:
- Omit Gemini Desktop entirely — excluded: confusing for users who know it's installed
- Custom popover menu — excluded: unnecessary complexity

## Decision 5: `ImportReviewView` Signature Change

**Decision**: Replace `let agent: AgentRecord` with `let source: ImportSource` in `ImportReviewView`. The navigation title uses `source.displayName`, and `applyDecisions()` calls `store.applyImportDecisions(toImport, agentId: nil)`.

**Rationale**: `ImportReviewView` never needed the full `AgentRecord` — it only used `agent.displayName` and `agent.id`. `ImportSource` provides both (id is now always `nil` for unregistered sources).

**No external research required**: all decisions are resolvable from the existing codebase. Config file formats (Claude Desktop, Gemini CLI, Codex CLI, Claude Code) are already implemented in their respective adapters.
