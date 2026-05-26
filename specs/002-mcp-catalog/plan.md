# Implementation Plan: MCP Server Catalog

**Branch**: `002-mcp-catalog` | **Date**: 2026-05-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-mcp-catalog/spec.md`

## Summary

Add a curated, searchable catalog of known MCP servers to mcp-inator. The catalog is bundled with the app as a JSON file (offline-first), supports manual refresh from a GitHub-hosted remote, and lets users add any entry to their library in one tap via a pre-filled `AddEditConfigView`. No agent config files are written at catalog-add time — the catalog is purely a discovery and quick-add mechanism feeding the existing library.

## Technical Context

**Language/Version**: Swift 5.9 (compiler 6.3.2)

**Primary Dependencies**: SwiftUI, GRDB (existing), Sparkle (existing), URLSession (stdlib — no new packages)

**Storage**: Catalog stored as JSON files only — no new GRDB tables.
- Bundle: `mcp-inator.app/Contents/Resources/catalog.json` (sole data source for v1)
- `catalog/catalog.json` at repo root is the source of truth; `make sync-catalog` (or `make build`) copies it to the bundle resource before each build

**Remote refresh**: Deferred to post-v1. The spec's FR-009/FR-010/FR-011 (manual refresh, error handling, last-refreshed timestamp) are out of scope until the repo hosting situation is resolved. Architecture supports adding it later with no structural changes.

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

### Phase A — Tooling

1. **`Makefile`** at repo root with targets:
   - `make build` — depends on `sync-catalog`; runs `xcodebuild` debug build
   - `make test` — runs `xcodebuild test`
   - `make lint` — runs `swiftlint lint`
   - `make run` — `make build` then kill + open the app
   - `make sync-catalog` — copies `catalog/catalog.json` → `mcp-inator/Resources/catalog.json`
   - `make clean` — `xcodebuild clean`

### Phase B — Data Layer (no UI)

2. **`CatalogEntry.swift`**: Define `CatalogEntry`, `CatalogEnvVar`, `CatalogCategory`, `CatalogMetadata`, `Catalog` as `Codable` structs/enums. Add `MCPServerConfig.init(from: CatalogEntry)` to `MCPServerConfig.swift`.

3. **`catalog/catalog.json`**: Create at repo root with ≥15 entries across ≥4 categories conforming to `contracts/catalog-json-schema.md`. Run `make sync-catalog` to copy to bundle; add bundle copy to Xcode Copy Bundle Resources build phase.

4. **`CatalogStore.swift`**: `@MainActor final class CatalogStore: ObservableObject` with:
   - `@Published var entries: [CatalogEntry]`
   - `func load()` — decodes bundle `catalog.json`; on schema version mismatch shows empty state rather than crashing
   - `func filtered(search: String, category: CatalogCategory?) -> [CatalogEntry]` — pure in-memory filter

5. **Unit tests** for `CatalogStore`: load from fixture JSON, search filter correctness, category filter, schema-version mismatch returns empty entries gracefully.

### Phase C — UI Layer

6. **`AddEditConfigView` prefill init**: Add `init(prefill: MCPServerConfig)` that pre-populates all `@State` fields but keeps `existing = nil` so saving creates a new library record.

7. **`CatalogDetailView.swift`**: Sheet showing entry name, description, category badge, command/URL + args, env vars list (name + description + required flag), docs link. "Add to Library" → `AddEditConfigView(prefill:)`. "Edit in Library" (when `serverKey` already in library) → `AddEditConfigView(existing:)`.

8. **`CatalogView.swift`**: Main catalog tab with:
   - Search bar (`searchText` binding)
   - Category filter (horizontal `Picker`; "All" + 7 categories)
   - `List` of filtered rows (name, category badge, description snippet, "in library" indicator)
   - Empty state when no results match

9. **`MenuBarView.swift`**: Add Catalog tab (third tab after Library and Agents). Inject `CatalogStore` via `.environmentObject`.

10. **`mcp_inatorApp.swift`**: Instantiate `CatalogStore` as `@StateObject`; inject via `.environmentObject`; call `catalogStore.load()` on init.

### Phase D — Catalog Content

11. **Populate `catalog/catalog.json`** with ≥15 well-known servers covering ≥4 categories (satisfies SC-006). Entries must include: GitHub, Slack, Linear, filesystem, Brave Search, PostgreSQL, SQLite, Puppeteer, fetch, memory, home-assistant, Notion, Google Drive, Docker, and at least one AI/LLM provider. Run `make sync-catalog` after populating.
