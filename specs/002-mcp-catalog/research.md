# Research: MCP Server Catalog

**Branch**: `002-mcp-catalog` | **Phase**: 0

---

## Decision 1: Catalog Data Source

**Decision**: Official MCP Registry (`registry.modelcontextprotocol.io`) as the upstream source, with a mcp-inator-maintained `catalog.json` as the app's actual data file.

**Rationale**: The registry has a stable, paginated REST API (`GET /v0.1/servers`) with all the install-time fields we need (`runtimeHint` → command, `packages[].identifier` + `packageArguments` → args, `environmentVariables` with `isSecret`, `websiteUrl`, `repository.url`). It is Anthropic-maintained so it won't disappear. However, the registry has no `category` field — we must curate our own taxonomy layer. The app therefore ships a hand-maintained `catalog.json` that is populated by pulling from the registry and adding categories. Remote refresh fetches an updated version of this mcp-inator-maintained file, not the registry directly.

**Alternatives considered**:
- mcpmarket.com — larger catalog but requires auth tokens and has pricing tiers; adds a third-party dependency
- glama.ai — no public API; web-scraping only
- Registry direct at refresh time — would require category inference logic in-app and expose the app to registry schema changes; complexity not warranted

---

## Decision 2: Remote Refresh Endpoint

**Decision**: `https://raw.githubusercontent.com/rayjohnson/mcp-inator/main/catalog/catalog.json`

**Rationale**: GitHub raw content has no rate limits (distinct from the API endpoint), is CDN-cached globally, supports ETags for conditional GET (minimises bandwidth), and has ~99.99% uptime. No separate hosting infrastructure needed — the catalog JSON lives in the repo alongside the app code, so catalog updates are just PRs.

**Alternatives considered**:
- GitHub Pages — adds a separate branch/workflow for a single static file; not justified
- GitHub Releases assets — designed for binaries; versioning overhead not needed for a JSON file
- Separate CDN/hosting — unnecessary operational cost

---

## Decision 3: Catalog Storage (App-Side)

**Decision**: JSON files only — no new GRDB tables. Bundled `catalog.json` in the app bundle (read-only fallback); refreshed copy in `~/Library/Application Support/mcp-inator/catalog.json` (writable). App always prefers the App Support copy if it exists and parses successfully; falls back to bundle.

**Rationale**: The catalog is read-only reference data, not user-editable records. GRDB is the right tool for the config library (mutable, relational, queried). JSON files are the right tool for a versioned data bundle that ships with the app and gets periodically replaced wholesale. Adding GRDB tables for catalog would complicate migrations and add no query benefit (search is done in-memory on a small array).

**ETag handling**: Last-fetched ETag stored in `UserDefaults` key `catalogETag`. Sent as `If-None-Match` header on refresh requests; a `304 Not Modified` response skips parsing and write.

**Alternatives considered**:
- GRDB catalog tables — adds migration complexity for no query benefit at 50–200 entries
- NSUbiquitousKeyValueStore / iCloud sync — out of scope; spec explicitly defers cross-machine sync

---

## Decision 4: In-App Search & Filter

**Decision**: In-memory `Array.filter` with `localizedCaseInsensitiveContains` on `displayName` and `shortDescription`. No database FTS, no third-party search library.

**Rationale**: At 50–200 entries, a full array scan completes in <1ms — well under the spec's 100ms keystroke requirement. `localizedCaseInsensitiveContains` handles Unicode and locale correctly. Adding SQLite FTS or a fuzzy search library would be premature optimisation.

---

## Decision 5: "Add to Library" Integration

**Decision**: `AddEditConfigView` gains a second initialiser `init(prefill: MCPServerConfig)` that pre-populates all `@State` fields but sets `existing = nil`, so saving creates a new library record (not an update). The catalog detail view constructs a `MCPServerConfig` from the `CatalogEntry` and passes it as `prefill`.

**Rationale**: `AddEditConfigView` already owns all the form state and validation logic. Reusing it avoids duplicating form UI. The `existing == nil` distinction already controls create-vs-update behaviour in `ConfigStore`.

**Alternatives considered**:
- Separate `CatalogAddView` — duplicates ~80% of `AddEditConfigView`; rejected
- Direct save from catalog (no form review) — violates spec assumption: "user still reviews and saves the pre-populated form"

---

## Decision 6: Category Taxonomy

**Decision**: Curated enum with 7 categories: `codeAndDevelopment`, `productivity`, `dataAndAnalytics`, `communication`, `infrastructure`, `aiAndLLMs`, `webAndBrowser`. Categories are assigned per-entry in `catalog.json` by the mcp-inator maintainers.

**Rationale**: The MCP Registry has no category field. A fixed, small enum keeps the filter UI simple and predictable. New categories can be added as the catalog grows (minor version bump per constitution).

---

## Decision 7: CatalogStore Architecture

**Decision**: `@MainActor final class CatalogStore: ObservableObject`, injected via `.environmentObject` alongside `ConfigStore`. Owns loading, refresh, search, and filter. Exposes `@Published var entries: [CatalogEntry]`, `@Published var lastRefreshedAt: Date?`, `@Published var isRefreshing: Bool`, `@Published var refreshError: String?`.

**Rationale**: Mirrors the existing `ConfigStore` pattern the codebase already uses. Keeping catalog logic separate from `ConfigStore` preserves the single-responsibility separation between "user library" and "discovery catalog".
