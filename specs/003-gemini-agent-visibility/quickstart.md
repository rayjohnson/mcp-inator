# Quickstart: Gemini Desktop Support + Agent Visibility Controls

## Gemini Desktop in the Agents Tab

1. Install the Gemini macOS app (bundle ID: `com.google.GeminiMacOS`).
2. Launch or restart mcp-inator — it scans for agents on startup.
3. Open the **Agents** tab. A **Gemini Desktop** row appears alongside the other agents.
4. Tap the row to open the agent view. You will see:
   > "Gemini Desktop manages MCP servers internally. Add servers directly in the Gemini app settings."
5. There are no server toggles and no "Change Path" button — mcp-inator cannot configure Gemini Desktop's MCP servers.

**Why**: Gemini Desktop supports MCP via HTTP/Streamable-HTTP transport only, and stores its configuration in an internal SQLite database. There is no external JSON config file mcp-inator can write to. To add MCP servers to Gemini Desktop, use the Gemini app's own settings UI.

## Hiding Agents You Don't Use

1. Open mcp-inator and navigate to the **Agents** tab.
2. Tap the gear icon (⚙) in the toolbar — this opens **Manage Agents**.
3. Toggle any agent row off to hide it. The change takes effect immediately.
4. Navigate back to the **Agents** tab — hidden agents are gone from the list.
5. Navigate to the **Servers** tab — config rows no longer show badges for hidden agents.
6. Open **PropagationView** (save or edit a config) — hidden agents do not appear as propagation targets.

**To restore a hidden agent**: Re-open **Manage Agents** and toggle it back on. All assignment states (which MCP servers were enabled/disabled) are fully restored — no re-configuration needed.

## Key Files Changed

| File | What changed |
|------|-------------|
| `mcp-inator/Adapters/AgentAdapter.swift` | Added `isAppManaged: Bool { false }` default |
| `mcp-inator/Adapters/GeminiDesktopAdapter.swift` | New file — detection-only, `isAppManaged = true` |
| `mcp-inator/Models/AgentRecord.swift` | Added `.geminiDesktop` to `AgentType`; added `isVisible` to `AgentRecord` |
| `mcp-inator/Store/Migrations/Migration004.swift` | Adds `isVisible` column |
| `mcp-inator/Store/ConfigStore.swift` | `visibleAgents`, `setAgentVisibility`, `fetchStatusMatrix` filter |
| `mcp-inator/UI/AgentListView.swift` | `isAppManaged` banner branch + `.geminiDesktop` adapter case |
| `mcp-inator/UI/AgentIcon.swift` | Gemini Desktop icon loading |
| `mcp-inator/UI/ManageAgentsView.swift` | New file — per-agent visibility toggles |
| `mcp-inator/UI/MenuBarView.swift` | `allAdapters` update + Agents tab toolbar button |
| `mcp-inator/UI/PropagationView.swift` | Uses `store.visibleAgents` |

## Running Tests

```bash
make test
```

Or for only the new tests:

```bash
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug test \
  -only-testing:mcp-inatorTests/GeminiDesktopAdapterTests \
  -only-testing:mcp-inatorTests/AgentVisibilityTests
```

## Implementation Notes

- `GeminiDesktopAdapter` is confirmed detection-only via binary analysis: the app stores MCP config in `~/Library/Application Support/com.google.GeminiMacOS/Data/*.store` (SQLite). Only HTTP transport is supported. If Google ships a file-based config path, only `GeminiDesktopAdapter` needs updating.
- `store.agents` remains the full unfiltered `@Published` array. `store.visibleAgents` is a computed filter (`agents.filter(\.isVisible)`). `ManageAgentsView` uses `store.agents`; `AgentsTabView` and `PropagationView` use `store.visibleAgents`.
- `ManageAgentsView` is a pushed `NavigationStack` view (consistent with app-wide navigation pattern).
- `fetchStatusMatrix()` is updated to filter on `isVisible = 1`, so badge rendering in `ConfigLibraryView` is automatically correct with no view-layer changes.
