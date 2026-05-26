# Implementation Plan: MCP Server Catalog

**Branch**: `002-mcp-catalog` | **Date**: 2026-05-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-mcp-catalog/spec.md`

## Summary

Add a curated, searchable catalog of known MCP servers to mcp-inator. The catalog is bundled with the app as a JSON file (offline-first), supports manual refresh from a GitHub-hosted remote, and lets users add any entry to their library in one tap via a pre-filled `AddEditConfigView`. No agent config files are written at catalog-add time — the catalog is purely a discovery and quick-add mechanism feeding the existing library.

## Technical Context

**Language/Version**: Swift 5.9 (compiler 6.3.2)

**Primary Dependencies**: SwiftUI, GRDB (existing), Sparkle (existing), URLSession (stdlib — no new packages)

**Storage**: Catalog stored as JSON files only — no new GRDB tables. Two locations:
- Bundle: `mcp-inator.app/Contents/Resources/catalog.json` (read-only fallback)
- App Support: `~/Library/Application Support/mcp-inator/catalog.json` (refreshed copy, preferred)
- ETag: `UserDefaults` key `catalogETag`

**Testing**: XCTest (existing Unit + Integration targets)

**Target Platform**: macOS 13.0+

**Project Type**: macOS menubar app (SwiftUI + AppKit)

**Performance Goals**:
- SC-002: Catalog tab opens and displays entries within 1 second (JSON load is synchronous; trivial at <200 entries)
- SC-003: Search results within 100ms per keystroke (in-memory filter; <1ms at scale)

**Constraints**: Offline-first; remote refresh must be non-blocking; no new package dependencies

**Scale/Scope**: Initial catalog ~15–25 entries across 7 categories; designed to grow to ~200 without architecture change

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Native macOS Experience | ✅ PASS | All new UI is SwiftUI; new tab in existing `TabView`; follows existing patterns |
| II. Single Source of Truth | ✅ PASS | Catalog is read-only discovery; library remains the authoritative config store |
| III. Non-Destructive Configuration | ✅ PASS | Catalog never writes agent files; "Add to Library" opens the review form |
| IV. Config Portability | ✅ PASS | Configs added from catalog go into the library and are assignable to any agent |
| V. Simplicity & Discoverability | ✅ PASS | This feature *is* the catalog principle from the constitution; directly addressed |

**Post-design re-check**: No violations introduced. `CatalogStore` is a separate class that does not touch `ConfigStore`'s GRDB pool. No new migrations. The `AddEditConfigView` change (adding `prefill:`) is additive and backward-compatible.

## Project Structure

### Documentation (this feature)

```text
specs/002-mcp-catalog/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/
│   └── catalog-json-schema.md   ← Phase 1 output
└── tasks.md             ← Phase 2 output (/speckit-tasks — not created here)
```

### Source Code

```text
mcp-inator/
├── Models/
│   ├── CatalogEntry.swift          NEW — CatalogEntry, CatalogEnvVar, CatalogCategory, CatalogMetadata, Catalog
│   └── MCPServerConfig.swift       MODIFY — add init(from:CatalogEntry) convenience init
├── Services/
│   └── CatalogStore.swift          NEW — load, refresh, search, filter; @MainActor ObservableObject
├── UI/
│   ├── CatalogView.swift           NEW — catalog tab: search bar + category filter + entry list
│   ├── CatalogDetailView.swift     NEW — sheet showing entry details + Add/Edit buttons
│   ├── AddEditConfigView.swift     MODIFY — add init(prefill:MCPServerConfig) for catalog pre-population
│   └── MenuBarView.swift           MODIFY — add Catalog tab to existing TabView
└── Resources/
    └── catalog.json                NEW — bundled catalog data (must be added to Xcode Copy Bundle Resources)

catalog/
└── catalog.json                    NEW — remote source file (hosted in repo; app fetches from GitHub raw URL)

mcp-inatorTests/
└── Unit/
    ├── CatalogStoreTests.swift     NEW
    └── CatalogEntryTests.swift     NEW
```

**Structure Decision**: Single project, existing layout. No new groups needed beyond `Services/`. Catalog JSON data lives in `catalog/` at the repo root (not inside the Xcode project folder) so it can be updated independently of app releases and fetched via GitHub raw URL.

## Complexity Tracking

No constitution violations — table not required.

---

## Implementation Phases

### Phase A — Data Layer (no UI)

1. **`CatalogEntry.swift`**: Define `CatalogEntry`, `CatalogEnvVar`, `CatalogCategory`, `CatalogMetadata`, `Catalog` as `Codable` structs/enums. Add `MCPServerConfig.init(from: CatalogEntry)` to `MCPServerConfig.swift`.

2. **`catalog.json` (bundle + remote)**: Create `catalog/catalog.json` at repo root with ≥15 entries across ≥4 categories conforming to the schema in `contracts/catalog-json-schema.md`. Copy to `mcp-inator/Resources/catalog.json` and add to Xcode Copy Bundle Resources build phase.

3. **`CatalogStore.swift`**: `@MainActor final class CatalogStore: ObservableObject` with:
   - `@Published var entries: [CatalogEntry]`
   - `@Published var isRefreshing: Bool`
   - `@Published var refreshError: String?`
   - `@Published var lastRefreshedAt: Date?`
   - `func load()` — reads App Support copy if valid, else bundle fallback
   - `func refresh() async` — conditional GET with ETag; non-blocking; updates App Support copy on success
   - `func filtered(search: String, category: CatalogCategory?) -> [CatalogEntry]` — pure in-memory filter

4. **Unit tests** for `CatalogStore`: load from fixture JSON, search filter correctness, refresh ETag round-trip (mocked URLSession), schema-version mismatch falls back to bundle.

### Phase B — UI Layer

5. **`AddEditConfigView` prefill init**: Add `init(prefill: MCPServerConfig)` that pre-populates all `@State` fields but keeps `existing = nil` so saving creates a new record.

6. **`CatalogDetailView.swift`**: Sheet view showing entry name, description, category badge, command/URL + args, env vars list (name + description + required flag), docs link. "Add to Library" button creates `MCPServerConfig(from: entry)` and navigates to `AddEditConfigView(prefill:)`. "Edit in Library" button (shown when `serverKey` already in library) navigates to `AddEditConfigView(existing:)`.

7. **`CatalogView.swift`**: Main catalog tab with:
   - Search bar (`searchText` binding)
   - Category filter (horizontal `Picker` or segmented; "All" + 7 categories)
   - `List` of filtered `CatalogEntry` rows (name, category badge, description snippet, "in library" indicator)
   - Empty state when no results match
   - Refresh button in toolbar (calls `catalogStore.refresh()`)
   - Last-refreshed timestamp in toolbar or footer

8. **`MenuBarView.swift`**: Add Catalog tab (third tab after Library and Agents). Inject `CatalogStore` via `.environmentObject`.

9. **`mcp_inatorApp.swift`**: Instantiate `CatalogStore` as `@StateObject`; inject via `.environmentObject`; call `catalogStore.load()` on init.

### Phase C — Remote Catalog Content

10. **Populate `catalog/catalog.json`** with ≥15 well-known servers covering ≥4 categories (satisfies SC-006). Entries must include: GitHub, Slack, Linear, filesystem, Brave Search, PostgreSQL, SQLite, Puppeteer, fetch, memory, home-assistant, Notion, Google Drive, Docker, and at least one AI/LLM provider.
