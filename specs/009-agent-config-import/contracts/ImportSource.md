# Contract: ImportSource

**Date**: 2026-05-29 | **Plan**: [../plan.md](../plan.md) | **Research**: [../research.md](../research.md)

`ImportSource` is a transient value type computed in `ConfigLibraryView` to represent one installed agent that may or may not be importable. It replaces the use of `AgentRecord` in the import flow, removing the requirement that an agent be registered in the database before it can appear in the Import menu.

---

## Type Definition

```swift
private struct ImportSource {
    let displayName: String
    let agentType: AgentType
    let adapter: any AgentAdapter
    let configPath: URL
    let isImportable: Bool
    let unavailableReason: String?
}
```

## Construction Rules

`ConfigLibraryView` computes `importSources: [ImportSource]` by iterating all known adapters:

```
for each adapter in [ClaudeCodeAdapter, ClaudeDesktopAdapter, GeminiCLIAdapter, CodexCLIAdapter, GeminiDesktopAdapter]:
    if NOT adapter.isInstalled()  → skip (not shown)
    if adapter.isAppManaged       → ImportSource(isImportable: false, unavailableReason: "…managed inside the app")
    if config file does not exist → skip (installed but no config yet — not shown)
    else                          → ImportSource(isImportable: true, unavailableReason: nil)
```

## UI Contract

| `isImportable` | Installed | Shown in menu? | Appearance |
|---------------|-----------|----------------|------------|
| `true`        | yes       | yes            | Normal enabled `Button` |
| `false`       | yes       | yes            | Greyed `Button(.disabled(true))` with `.help(unavailableReason)` tooltip |
| —             | no        | no             | Hidden entirely |

If all `ImportSource` values have `isImportable == false`, the Import menu button MUST still appear (so users understand why import is unavailable). If `importSources` is empty (no agents installed), the Import button MUST be hidden.

## Interaction with `ImportReviewView`

`ImportReviewView` is updated to accept `source: ImportSource` instead of `agent: AgentRecord`:

- Navigation title: `"Import from \(source.displayName)"`
- On confirm: calls `store.applyImportDecisions(decisions, agentId: nil)`
  - `nil` agentId → configs are added to the library only; no agent assignment is created

## Compatibility

The existing `DiscoveryView` first-run flow does **not** use `ImportSource` or `ImportReviewView` — it uses `DiscoveryView` which takes `[ConfigStore.DiscoveryResult]`. No changes to the discovery flow are required.
