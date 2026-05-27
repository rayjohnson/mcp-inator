# Implementation Plan: Catalog Registry Integration

**Branch**: `005-catalog-registry-integration` | **Date**: 2026-05-26 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) | **Research**: [research.md](research.md) | **Data model**: [data-model.md](data-model.md)

---

## Summary

Replace the hand-curated `catalog.json` bundle with live data from the MCP registry at `registry.modelcontextprotocol.io`. The registry supports keyword search (`?search=<term>`); each category in the browse UI maps to one search term, results cached locally on first launch. Users can also search the full 30k-server registry live. Env var names from registry data are shown as editable hints, clearly marked "Suggested — verify with package docs."

`CatalogStore` and `catalog.json` are deleted entirely. `RegistryStore` (new) replaces `CatalogStore` as the `@EnvironmentObject` for catalog-related UI. `RegistryClient` (new) is the network boundary — injectable for testing.

---

## Technical Context

**Language/Version**: Swift 5.9+

**Primary Dependencies**: SwiftUI (UI), Foundation / URLSession (network), GRDB (config store, unchanged), Sparkle (auto-update, unchanged), MCP package (MCP server subprocess)

**Storage**: JSON file at `~/Library/Application Support/mcp-inator/registry-cache.json` (new, category cache); existing SQLite DB (config store, unchanged)

**Testing**: XCTest; `@MainActor` test classes matching production actors

**Target Platform**: macOS 13+ (menu bar app)

**Project Type**: macOS desktop application (status bar / menu bar)

**Performance Goals**: First-launch category population ≤ 10 s (SC-001); subsequent-launch category display: immediate from cache (SC-002); live search results ≤ 3 s after pause (SC-004)

**Constraints**: All registry activity in background tasks — app launch time unaffected (SC-006); offline usability via local cache (SC-003); no registry auth required

**Scale/Scope**: 7 categories × 1 API call each on first launch; ~100 entries per category; 1 live search call per debounce cycle; cache file ~350 KB worst case

---

## Testability Design Constraints

These are explicit architectural requirements, not implementation suggestions. They must be respected in the task breakdown and implementation.

1. **`RegistryClient` protocol** (`contracts/registry-client.md`): All network calls go through this protocol. `RegistryStore` takes `any RegistryClient` in its initializer. Tests inject `StubRegistryClient`. No `URLSessionRegistryClient` usage outside of production wiring.

2. **Pure transformation functions**: `filterLatest`, `deduplicate`, `RegistryEntry.init?(raw:)`, `deriveCommand(packageType:identifier:)`, and `displayName(from:)` are free/static functions with no side effects. Tests call them directly with fixture data — no async, no mocks needed.

3. **Injectable cache storage path**: `RegistryStore.init(client:cacheURL:)` accepts an explicit cache file URL. Tests use a `FileManager.default.temporaryDirectory` path for isolation. Production uses `RegistryStore.defaultCacheURL`.

4. **Observable state separate from UI**: `RegistryStore` exposes `categoryStates: [CatalogCategory: CategoryCacheState]` and `searchState: SearchState` as `@Published` properties. Tests assert on these directly without instantiating views.

5. **`EnvVar.isHint` not persisted**: Excluded from `CodingKeys`, never written to DB or agent config files. Tests confirm it is absent from encoded output and defaults to `false` on decode.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Assessment | Notes |
|-----------|-----------|-------|
| I. Native macOS Experience | ✅ Pass | Registry fetches run in background Tasks; UI is non-blocking; Application Support cache follows macOS conventions |
| II. Single Source of Truth | ✅ Pass | Registry data populates browse/search only; user-saved configs remain in the SQLite store; registry is supplemental, not authoritative |
| III. Non-Destructive Configuration | ✅ Pass | Adding a server from registry creates a new library entry; no existing configs modified; hint env vars require explicit user save |
| IV. Config Portability | ✅ Pass | No change to adapter layer or config application flow |
| V. Simplicity & Discoverability | ✅ Pass (with trade-off noted) | Replaces broken static catalog with live registry data. **Trade-off**: true first-launch-offline users see an empty catalog until they connect once. The constitution requires a catalog "always available" — the registry cache satisfies this for returning users. A bundled seed cache could close the gap for new users; deferred to a future iteration. |

**Quality Standards**:
- New `RegistryClient` protocol + `URLSessionRegistryClient` need unit tests (fixture JSON decoding)
- New transformation functions (filter, dedup, derive) need unit tests
- `RegistryStore` state transitions need unit tests with `StubRegistryClient`
- `CatalogStoreTests.swift` replaced by `RegistryStoreTests.swift`

---

## Project Structure

### Documentation (this feature)

```text
specs/005-catalog-registry-integration/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── contracts/
│   └── registry-client.md
└── tasks.md             ← Phase 2 output (/speckit-tasks — not created by /speckit-plan)
```

### Source Code

```text
mcp-inator/
├── App/
│   └── mcp_inatorApp.swift         MODIFY: CatalogStore → RegistryStore; trigger populateCategories()
├── MCP/
│   ├── MCPServer.swift             MODIFY: CatalogStore → RegistryStore
│   └── MCPTools.swift              MODIFY: CatalogStore → RegistryStore; update list_catalog impl
├── Models/
│   ├── CatalogEntry.swift          MODIFY: keep CatalogCategory enum; delete all other types
│   ├── MCPServerConfig.swift       MODIFY: EnvVar.isHint field; MCPServerConfig.init(from: RegistryEntry)
│   └── RegistryEntry.swift         NEW: RegistryEntry, RegistryEnvVar, PackageType, RemoteTransportType
├── Services/
│   ├── CatalogStore.swift          DELETE
│   ├── RegistryClient.swift        NEW: RegistryClient protocol, URLSessionRegistryClient, raw API structs,
│   │                                    filterLatest(), deduplicate() pure functions
│   └── RegistryStore.swift         NEW: RegistryStore, CategoryCacheState, SearchState,
│                                        RegistryCacheFile, category keyword map
└── UI/
    ├── AddEditConfigView.swift      MODIFY: EnvVarRow shows hint badge when isHint == true
    ├── CatalogDetailView.swift      MODIFY: use RegistryEntry; env var hint treatment in detail
    └── CatalogView.swift            MODIFY: use RegistryStore; per-category loading state; live search

Resources/
└── catalog.json                     DELETE
```

```text
mcp-inatorTests/
├── Unit/
│   ├── CatalogEntryTests.swift       MODIFY: update to test MCPServerConfig.init(from: RegistryEntry)
│   ├── CatalogStoreTests.swift       DELETE (replaced by RegistryStoreTests)
│   ├── MCPToolHandlerTests.swift     MODIFY: CatalogStore() → RegistryStore()
│   ├── RegistryClientTests.swift     NEW: fixture JSON decoding, filterLatest, deduplicate
│   ├── RegistryEntryTests.swift      NEW: deriveCommand, displayName derivation, isActionable, isHint
│   └── RegistryStoreTests.swift      NEW: state transitions, cache load/save, offline fallback, search states
├── Integration/
│   └── MCPServerTests.swift          MODIFY: verify list_catalog tool still present (count stays 7)
└── Fixtures/
    └── registry-response.json        NEW: sample API response for decoder tests
```

**Structure Decision**: Single project, existing layout. New files added in-place alongside existing source. No new targets, no new frameworks.

---

## Complexity Tracking

No constitution violations. No complexity justification required.

---

## Implementation Notes

### RegistryStore initialization

`RegistryStore` init is synchronous — it loads the cache file from disk, populates `categoryStates` with `.loaded(...)` for any categories that have cached data, and leaves uncached categories as `.uncached`. The async `populateCategories()` method is called by the app entry point after init.

```swift
@MainActor
final class RegistryStore: ObservableObject {
    @Published private(set) var categoryStates: [CatalogCategory: CategoryCacheState]
    @Published private(set) var searchState: SearchState = .idle

    init(client: any RegistryClient = URLSessionRegistryClient(),
         cacheURL: URL = RegistryStore.defaultCacheURL)

    func populateCategories() async             // background refresh, updates categoryStates
    func refreshCategory(_ c: CatalogCategory) async  // retry a single failed/uncached category
    func search(query: String) async           // live search, updates searchState
    func cancelSearch()                        // called when search text cleared

    static var defaultCacheURL: URL            // Application Support/mcp-inator/registry-cache.json
}
```

### Concurrent category fetching

`populateCategories()` fetches all 7 categories using `async let` or a `TaskGroup` for concurrency. Each category result is written to `categoryStates` on `@MainActor` as it arrives. Categories that already have cache data show `.loaded` state immediately; the `.loading` state is only shown for categories with no prior data.

### Live search debounce (in CatalogView)

```swift
// CatalogView
@State private var searchTask: Task<Void, Never>?

.onChange(of: searchText) { query in
    searchTask?.cancel()
    guard !query.isEmpty else { registryStore.cancelSearch(); return }
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await registryStore.search(query: query)
    }
}
```

### CatalogView state logic

When `searchText` is non-empty: show `searchState` (live results or fallback).
When `searchText` is empty: show category picker + per-category state from `categoryStates`.

For each category in the picker, show:
- `.uncached` / `.loading`: skeleton/spinner
- `.loaded(_, entries)`: server list (may be empty → "No servers in this category yet")
- `.failed`: error message with retry button

### Search cancellation guard

`search(query:)` must guard against race conditions where a cancelled in-flight request completes and overwrites a newer state. Pattern:

```swift
func search(query: String) async {
    searchState = .searching
    do {
        let results = try await client.search(query: query, pageSize: 100)
        guard !Task.isCancelled else { return }
        searchState = results.isEmpty ? .empty : .results(results)
    } catch let error as URLError where error.code == .notConnectedToInternet
                                     || error.code == .networkConnectionLost {
        guard !Task.isCancelled else { return }
        searchState = .localOnly(cachedFilter(query: query))
    } catch {
        guard !Task.isCancelled else { return }
        searchState = .failed(message: error.localizedDescription)
    }
}
```

The `guard !Task.isCancelled` before each state assignment ensures that if the view's debounce task is cancelled, a stale result from a slow request never lands.

### MCPToolHandler update

`MCPToolHandler.init` parameter changes: `catalogStore: CatalogStore` → `registryStore: RegistryStore`. `listCatalog()` returns entries from `registryStore.entries(for:)` across all categories, deduplicated. Output shape is unchanged (same JSON fields, `isVerified` always `false`).

### Removing catalog.json

The bundle resource `catalog.json` is removed from the Xcode project target. `CatalogStore.swift` is deleted from the filesystem and removed from the project. `CatalogEntry.swift` is edited in-place to remove everything except `CatalogCategory`.
