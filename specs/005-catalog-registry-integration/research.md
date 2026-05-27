# Research: Catalog Registry Integration

**Phase**: 0 — Research
**Branch**: `005-catalog-registry-integration`
**Spec**: [spec.md](spec.md)

---

## Decision 1: Registry API Endpoint & Pagination

**Decision**: Use `GET https://registry.modelcontextprotocol.io/v0/servers?search=<q>&pageSize=100`. Filter to `isLatest: true` entries client-side. Do not paginate.

**Rationale**: Endpoint confirmed working via live probing. `isLatest` lives at `_meta["io.modelcontextprotocol.registry/official"].isLatest`. A pageSize of 100 captures enough results per category search for a useful browse experience — a category showing 10–30 servers is better than 5,000. Pagination would add complexity and latency for negligible benefit in a browse context. Live search uses the same endpoint.

**Response shape**:
```json
{
  "servers": [
    {
      "server": {
        "name": "io.github.Author/server-name",
        "description": "...",
        "version": "1.0.0",
        "packages": [
          {
            "registryType": "npm",
            "identifier": "@author/server-name",
            "environmentVariables": [
              { "name": "API_KEY", "description": "...", "isRequired": true, "isSecret": true }
            ],
            "transport": { "type": "stdio" }
          }
        ],
        "remotes": [
          {
            "type": "streamable-http",
            "url": "https://example.com/mcp",
            "headers": [
              { "name": "Authorization", "value": "Bearer {api_key}", "isSecret": true }
            ]
          }
        ],
        "repository": { "url": "https://github.com/...", "source": "github" }
      },
      "_meta": {
        "io.modelcontextprotocol.registry/official": {
          "isLatest": true,
          "status": "active"
        }
      }
    }
  ],
  "metadata": { "count": 30, "nextCursor": "some:cursor" }
}
```

**Alternatives considered**:
- Full server list download: ruled out — 29,713 servers, no practical way to download on launch
- Popularity sort: registry does not expose a popularity/download metric

---

## Decision 2: Cache Storage Format

**Decision**: JSON file at `~/Library/Application Support/mcp-inator/registry-cache.json`.

**Rationale**: Standard macOS location for app data that persists across app updates. Easy to delete manually for testing. Readable by both the GUI app and the MCP subprocess (same binary, same Application Support path). No DB schema migration required. Practical size ceiling is well within bounds — 7 categories × 100 entries × ~500 bytes/entry ≈ 350 KB.

**Cache file format**:
```json
{
  "version": 1,
  "categories": {
    "Code & Development": {
      "fetchedAt": "2026-05-26T12:00:00Z",
      "entries": [ ... ]
    }
  }
}
```

**Alternatives considered**:
- New SQLite table (GRDB migration): overkill for a cache; complicates schema versioning
- UserDefaults: practical ~1 MB limit could be exceeded; not designed for structured collections
- Per-category files: more disk I/O, no clear benefit over a single file

---

## Decision 3: Offline Detection

**Decision**: Catch `URLError.notConnectedToInternet` and `URLError.networkConnectionLost` from URLSession calls in `URLSessionRegistryClient`. Propagate as a typed error that `RegistryStore` recognizes and uses to trigger the cached-results fallback path.

**Rationale**: No additional framework needed. The `RegistryClient` protocol boundary means tests can simulate offline by throwing a `URLError` from a stub — no real network disconnection needed. Covers the common Wi-Fi-off and airplane-mode cases.

**Alternatives considered**:
- `Network.framework` `NWPathMonitor`: more granular (distinguishes cellular vs. Wi-Fi), but adds complexity for a simple "offline → show cache" requirement. Can be added later if needed.
- Pre-flight reachability check: unnecessary — the URLSession error on failure is the natural signal.

---

## Decision 4: Search Debounce

**Decision**: Task cancellation pattern in the view. The view holds a `@State private var searchTask: Task<Void, Never>?`. On text change: cancel `searchTask`, create new task with `try? await Task.sleep(for: .milliseconds(300))` before calling `registryStore.search(query:)`.

**Rationale**: Pure Swift concurrency — no Combine dependency. The store's `search(query:)` method is a plain `async` function that fetches and updates `@Published searchState`, making it directly callable in tests without any debounce machinery. The debounce lives entirely in the view layer where it belongs.

**Alternatives considered**:
- Combine `debounce(for:)` on a Publisher: adds a Combine publisher chain to the store, mixing scheduling concerns with data management.
- Debounce in `RegistryStore`: makes the store harder to test (callers must wait for the debounce timer).

---

## Decision 5: Display Name Derivation

**Decision**: Pure function `RegistryEntry.displayName(from registryName: String) -> String`:
1. Take the component after the last `/` (e.g., `postgres-mcp` from `io.github.YawLabs/postgres-mcp`)
2. Strip common noise suffixes: `-mcp-server`, `-mcp-servers`, `-mcp`, `-server`
3. Replace hyphens and underscores with spaces
4. Title-case the result

**Examples**: `io.github.YawLabs/postgres-mcp` → `Postgres` | `ai.smithery/github` → `Github` | `com.foo/home-assistant-mcp-server` → `Home Assistant`

**Rationale**: Registry names follow a `<publisher>/<server-name>` convention consistently. The suffix stripping removes noise that otherwise makes display names redundant (every name would end in "Mcp"). This function is pure and easy to unit test with a fixture table.

**Alternatives considered**:
- Use description text: too long, not structured
- Use full registry name: too long, includes publisher namespace

---

## Decision 6: Category Assignment

**Decision**: Assign `CatalogCategory` at fetch time — each fetch call knows which category it's populating, so all results from that call are tagged with that category.

**Category keyword map** (one primary term per category for V1):

| Category | Search Term |
|----------|------------|
| Code & Development | `github` |
| Productivity | `notion` |
| Data & Analytics | `postgres` |
| Communication | `slack` |
| Infrastructure | `docker` |
| AI & LLMs | `openai` |
| Web & Browser | `browser` |

**Rationale**: We define what goes in each category by choosing the search term — no content analysis needed. Single term per category means one API call per category (7 total on first launch), keeping first-launch time well inside the 10-second SC-001 target. Terms will be tuned editorially with app updates.

**Alternatives considered**:
- Multiple terms per category, merged and deduplicated: more results but ~21 API calls vs. 7; adds merge/dedup complexity. Reserved for a future iteration.
- Content classification of description text: unreliable, adds complexity, not needed.

---

## Decision 7: `isHint` on EnvVar

**Decision**: Add `var isHint: Bool = false` to `EnvVar`, excluded from `CodingKeys` so it is never persisted to the database or written to agent config files. Set to `true` only when creating `MCPServerConfig` from a `RegistryEntry` via `MCPServerConfig.init(from: RegistryEntry)`.

**Rationale**: The hint flag is purely a UI affordance for the "new server from catalog" flow. Once the user saves, the env vars become theirs — no semantic difference from manually typed values. Excluding from `CodingKeys` avoids any DB schema change (Migration005 not needed for this).

**Alternatives considered**:
- Separate `hints: [EnvVar]` parameter to `AddEditConfigView`: conceptually cleaner (hints are not env vars until confirmed), but requires threading an extra parameter through the prefill path and changing the view interface.
- Store hint flag in DB: leaks catalog metadata into the config store; wrong layer.

---

## Decision 8: RegistryStore Replaces CatalogStore

**Decision**: `RegistryStore` is a new class that entirely replaces `CatalogStore`. `CatalogStore.swift` is deleted. `catalog.json` bundle resource is removed. Any remaining references to `CatalogStore` are updated to `RegistryStore`.

**Rationale**: `CatalogStore` has no reusable logic — it just loads a JSON bundle into `[CatalogEntry]`. The new store has a fundamentally different behavior (async network, cache I/O, state machine). Extending vs. replacing would create a confusing hybrid. The spec explicitly calls for removing the bundle-load path.

**Alternatives considered**:
- Keep `CatalogStore` as an offline-only fallback: spec explicitly removes it. The registry cache is the offline fallback.

---

## Decision 9: RegistryEntry vs. CatalogEntry

**Decision**: Introduce `RegistryEntry` as the new browse model. Keep `CatalogCategory` enum (it's UI-level, not coupled to the data source). Remove `CatalogEntry`, `CatalogEnvVar`, `CatalogMetadata`, `Catalog` structs. Add `MCPServerConfig.init(from: RegistryEntry)`.

**Rationale**: `CatalogEntry` fields like `isVerified`, `command` (pre-computed), and `url` (pre-filled) don't map cleanly to registry data — registry entries need command derivation and don't have a verified status. A clean `RegistryEntry` model with derived properties is easier to test and reason about than shoehorning registry data into `CatalogEntry`.

**Alternatives considered**:
- Map `RegistryEntry` → `CatalogEntry` as the app model: keeps downstream code unchanged but hides the derivation logic in a mapping layer and perpetuates the `isVerified` fiction.

---

## Decision 10: OCI (Docker) Command Derivation

**Decision**: Derive `docker run <identifier>` for OCI packages. Document as a known limitation that non-standard docker flags are not supported.

**Rationale**: Standard invocation for OCI-packaged MCP servers. Users who need additional flags (volume mounts, network settings) can edit the generated config in the library. This is consistent with how npm and pypi derivations work — they're starting points, not guaranteed-complete configs.

---

## Resolved Clarifications

All `NEEDS CLARIFICATION` items from the spec were resolved:
- Cache storage format: JSON file in Application Support (see Decision 2)
- Offline detection mechanism: URLError catching (see Decision 3)
- Debounce implementation: Task cancellation in view (see Decision 4)
- Display name derivation: pure function, component after last `/` + cleanup (see Decision 5)
