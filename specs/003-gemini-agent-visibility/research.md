# Research: Gemini Desktop Support + Agent Visibility Controls

## R-001: Gemini Desktop MCP Support (Binary Analysis)

**Decision**: Gemini Desktop is a detection-only agent. mcp-inator shows it in the Agents tab but cannot read or write its MCP configuration.

**Findings from binary analysis of `/Applications/Gemini.app`**:
- The binary contains `McpServer`, `mcpServersArray`, `_mcpServers`, `StreamableHttpTransport`, `sseReadTimeout`, and `GAIGLTool_McpServer_StreamableHttpTransport` — MCP is real and built in.
- Only `StreamableHttpTransport` is present (no stdio). Gemini Desktop connects to remote HTTP/SSE MCP servers only; it does not spawn local processes.
- MCP config is stored in the app's internal SQLite databases (`~/Library/Application Support/com.google.GeminiMacOS/Data/*.store`), not in a JSON file.
- There is no external config file path mcp-inator can read from or write to.

**Rationale for detection-only approach (Option A)**:
- Silently omitting a detected app creates user confusion ("why isn't Gemini Desktop in the list?").
- Pretending we can manage its config would be deceptive.
- Detection-only with an honest "managed in-app" banner is accurate and future-proof: if Google exposes a file-based config path, only the adapter needs updating.

**Alternatives considered**:
- File-based adapter with provisional path — rejected: the path doesn't exist and Google hasn't documented one. Would always show "unavailable" in a misleading way.
- Defer entirely — rejected: the user explicitly installed the app and expects it to appear. The visibility feature (US2) makes this more useful, not less.

---

## R-002: `AgentAdapter` Protocol Extension for App-Managed Agents

**Decision**: Add `var isAppManaged: Bool { get }` to the `AgentAdapter` protocol with a default implementation returning `false`. `GeminiDesktopAdapter` overrides to return `true`.

**Rationale**: A single Boolean on the protocol is the minimal change needed to let `AgentListView` distinguish "unavailable (file missing)" from "managed in-app (by design)". No new types, no new protocols. All existing adapters get the default without any changes.

**How `AgentListView` uses it**:
- `isAppManaged == true` → show "in-app managed" banner, no toggle list, no "Change Path" button.
- `isAppManaged == false` + `!agent.isAvailable` → existing "Config file not accessible" + "Change Path" banner.
- `isAppManaged == false` + `agent.isAvailable` → normal toggle list.

---

## R-003: Agent Detection (Gemini Desktop)

**Decision**: `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS")` as primary, `/Applications/Gemini.app` existence as fallback.

**Rationale**: Bundle ID `com.google.GeminiMacOS` is confirmed from `~/Library/Application Support/com.google.GeminiMacOS/`. `NSWorkspace` handles non-standard install locations. Same pattern as `ClaudeDesktopAdapter`.

**App icon**: `NSWorkspace.shared.icon(forFile: appURL.path)` using the resolved URL. Falls back to blue "G" `LetterBadge`.

---

## R-004: Agent Visibility Storage

**Decision**: `isVisible: Bool` (INTEGER 1/0 in SQLite) on `AgentRecord`. Added via `Migration004`. Exposed as `store.visibleAgents` computed property.

**Rationale**: A DB column keeps all agent state co-located. `store.agents` stays as the full unfiltered `@Published` array (used by ManageAgentsView and tests). `store.visibleAgents` is a computed filter on top. No `@Published` for the filtered view — SwiftUI re-renders `AgentsTabView` reactively when `store.agents` changes.

**Alternatives considered**:
- `UserDefaults` — diverges from GRDB pattern, harder to query.
- Separate `agent_visibility` table — over-engineered for one Boolean.
- Changing `store.agents` to be pre-filtered — breaks ManageAgentsView (needs all agents) and existing tests.

---

## R-005: Visibility Scope

**Decision**: `isVisible` filters three surfaces:

| Surface | Filter by isVisible |
|---------|---------------------|
| Agents tab list (`AgentsTabView`) | ✓ use `store.visibleAgents` |
| Servers tab agent badges (`fetchStatusMatrix`) | ✓ filter in store query |
| PropagationView agent list | ✓ filter to visible agents |
| ManageAgentsView | ✗ shows all agents |
| DiscoveryView | ✗ shows all agents |

**Rationale for PropagationView**: User confirmed that hidden agents should not appear in PropagationView. Hiding means "I don't want to manage this agent" — including during propagation.

---

## R-006: Edit Sites for `AgentType` Switch

All locations requiring `.geminiDesktop` handling:

| File | Location | Change |
|------|----------|--------|
| `Models/AgentRecord.swift` | `AgentType` enum | New case + displayName + defaultConfigPath |
| `UI/AgentListView.swift` | `private var adapter` switch | Add `.geminiDesktop: GeminiDesktopAdapter()` |
| `UI/AgentListView.swift` | `restartMessageText` | No-op for app-managed (banner shown instead) |
| `UI/AgentIcon.swift` | body switch | Load Gemini Desktop app icon |
| `UI/DiscoveryView.swift` | `adapters` dict | Add `.geminiDesktop: GeminiDesktopAdapter()` |
| `UI/MenuBarView.swift` | `allAdapters` | Add `GeminiDesktopAdapter()` |
| `App/mcp_inatorApp.swift` | adapter scan list | Add `GeminiDesktopAdapter()` |
