# Private Catalog Sources — Design Spec

## Goal

Allow users to configure one or more private catalog URLs in Preferences. Each private catalog appears as its own tab (named by the catalog JSON itself), visible only to users who configure the URL. Public users see no change.

---

## JSON Format

Each private catalog is a single hosted JSON file:

```json
{
  "tabName": "Moov Internal",
  "servers": [
    {
      "id": "moov-internal-server",
      "displayName": "Internal Tool",
      "category": "developer-tools",
      "shortDescription": "Our internal data pipeline MCP server.",
      "command": "npx",
      "args": ["-y", "@moov/internal-mcp"],
      "envVars": [...]
    }
  ]
}
```

- `tabName`: displayed as the tab label in the UI
- `servers`: array using the **exact same `CatalogEntry` format** as the public catalog (`servers.json`). All existing fields are valid. Stats/metrics are not fetched — `CatalogViewModel` handles nil metrics gracefully.
- No auth. URLs are assumed accessible (private network, VPN, or public-but-unlisted).

---

## Data Model

### New Swift types

**`PrivateCatalogResponse: Codable`** — decodes the envelope:
```swift
struct PrivateCatalogResponse: Decodable {
    let tabName: String
    let servers: [CatalogEntry]
}
```

**`PrivateCatalogSource`** — runtime value representing a successfully loaded source:
```swift
struct PrivateCatalogSource: Identifiable {
    let url: String          // configured URL (used as stable id)
    let tabName: String      // from JSON
    let entries: [CatalogViewModel]
}
```

**`PrivateCatalogPreferences`** — `UserDefaults`-backed storage for configured URLs:
```swift
enum PrivateCatalogPreferences {
    static var urls: [String]  // key: "privateCatalogURLs"; default: []
}
```

Same enum-with-static-computed-properties pattern as `SharingPreferences`, backed by `UserDefaults.standard`.

---

## Store & Fetching

**`PrivateCatalogStore`** — `@MainActor final class`, `ObservableObject`. Injected `URLSession` for testability.

### Published state
```swift
@Published var sources: [PrivateCatalogSource] = []
```

### Fetch flow
1. Read configured URLs from `PrivateCatalogPreferences`
2. Deduplicate URLs
3. Fetch all concurrently via `withTaskGroup` (15-second timeout per request, matching `CatalogClient`)
4. For each URL: decode `PrivateCatalogResponse` → build `[CatalogViewModel]` → produce `PrivateCatalogSource`
5. On failure: fall back to per-URL cache; if cache also missing, silently skip that source
6. Update `sources` on main actor

### Caching
Each URL's response cached to:
```
~/Library/Application Support/mcp-inator/private-catalog-{sha256(url)}.json
```
Same network-first, cache-on-failure pattern as `CatalogClient`.

### Lifecycle
- `fetchIfNeeded()` called once at app launch alongside `catalogStore.fetchIfNeeded()`
- Called again immediately when the user adds or removes a URL in Preferences — tabs appear/disappear without restarting

---

## Preferences UI

New **"Private Catalogs"** section added to `PreferencesView` below the existing sections.

- Lists configured URLs, one per row, with a remove (×) button per row
- "Add" text field + button at the bottom
- No URL validation beyond non-empty check — if a URL is unreachable or returns bad JSON, that tab simply won't appear (no error dialog)
- Adding or removing a URL triggers `privateCatalogStore.fetchIfNeeded()` immediately

---

## Tab Display

`MenuBarView` and `MainWindowView` gain additional dynamic tabs via `ForEach` over `privateCatalogStore.sources`. Tabs appear after the public "Catalog" tab.

```
[ Servers ]  [ Agents ]  [ Catalog ]  [ Moov Internal ]  [ Other Source ]
```

- Tab icon: `"building.2"` (distinguishes private tabs from public "Catalog")
- Tab name: `source.tabName` from the catalog JSON
- Each private tab renders a standard `CatalogView` — the same view used for the public catalog
- Since private entries have no `editorialRank` or stats, the Featured/Discover sections won't render; the category filter and search work as-is

`PrivateCatalogStore` is injected as an `@EnvironmentObject` from the app entry point, alongside the existing `CatalogStore`.

---

## Testability

- `PrivateCatalogStore` accepts an injected `URLSession` — tests use `MockURLProtocol` to serve fake responses
- `PrivateCatalogPreferences` uses `UserDefaults.standard` — tests set/read keys directly and clean up in `tearDown` (same pattern as `PingServiceTests`)

### Key behaviors to test
- Configured URLs are fetched and produce correct `tabName` and entry count
- A failed/unreachable URL is silently skipped; other sources still load
- Cache fallback works when network fails
- Adding a duplicate URL is deduplicated (appears only once)
- `sources` array order matches configured URL order

---

## What Is Not In Scope

- Authentication for private catalog URLs
- Validating URL reachability in Preferences before saving
- Merging private entries into the public Catalog tab
- Any backend changes
- Per-source refresh controls or cache invalidation UI
