# Research: Library Search & Filter

## Decision 1: Filter location — view-local vs ConfigStore method

**Decision**: Filter in the view using a local computed property on `filteredConfigs`.

**Rationale**: The search query is ephemeral UI state with no persistence requirement. Adding a `filtered(query:)` method to `ConfigStore` would pollute the service layer with display logic. The Catalog tab uses the same view-local pattern successfully (see `CatalogView.swift` lines 152–159).

**Alternatives considered**: Adding a `@Published var searchText` + computed `filteredConfigs` to `ConfigStore` — rejected because it mixes display state into the data layer.

---

## Decision 2: SwiftUI search mechanism — `.searchable()` vs manual `TextField`

**Decision**: Use SwiftUI's `.searchable(text:prompt:)` modifier.

**Rationale**: `.searchable()` is the established pattern already used in `CatalogView`. It places the search field in the correct macOS toolbar position, provides the native clear button (×), and handles Escape-to-clear keyboard shortcut automatically. No need to reinvent this.

**Alternatives considered**: A manual `TextField` in the list header — rejected because it requires manual keyboard handling, doesn't match macOS HIG toolbar placement, and duplicates what `.searchable()` provides for free.

---

## Decision 3: Search reset on tab switch

**Decision**: Use `.onDisappear { searchText = "" }` on `ConfigLibraryView`.

**Rationale**: The spec requires search to reset when the user leaves the Servers tab. `.onDisappear` fires when the view is navigated away from in both the menu bar popover and the dock-mode NavigationSplitView.

**Alternatives considered**: Resetting via `.onChange(of: selectedTab)` in a parent view — rejected because it leaks tab knowledge into the parent and is fragile.

---

## Decision 4: Match fields

**Decision**: Match against `displayName` and `displayCommand` (the combined command+args string already computed by `MCPServerConfig`).

**Rationale**: These are the two fields visible in `ConfigRow` — name (bold) and the command line (caption). Matching only what the user can see prevents confusing "why did this result appear?" moments. `serverKey` is a derived slug of the display name so matching it adds marginal value.

**Alternatives considered**: Also matching `serverKey` and `url` (for HTTP servers) — `url` will be added as a match field for HTTP/SSE servers since it's visible in the row.

---

## Decision 5: Drag-to-reorder during search

**Decision**: No action needed — drag-to-reorder is not currently implemented in `ConfigLibraryView`.

**Rationale**: Inspecting `ConfigLibraryView.swift`, the `ForEach(store.configs)` has no `.onMove` modifier. There is no reorder gesture to disable. The spec assumption about disabling reorder during search is noted but moot.

---

## Existing code patterns (key facts)

- `ConfigLibraryView.swift` — the Servers tab view. Uses `store.configs` directly.
- `MCPServerConfig` — has `displayName: String`, `displayCommand: String` (computed, combines command + first arg), `url: String`, `isHTTP: Bool`.
- `ConfigStore.configs: [MCPServerConfig]` — `@Published`, source of truth.
- `CatalogView.swift` line 10: `@State private var searchText: String = ""`
- `CatalogView.swift` line 27: `.searchable(text: $searchText, prompt: "Search catalog…")`
- Filter pattern: `name.localizedCaseInsensitiveContains(query) || ...`
