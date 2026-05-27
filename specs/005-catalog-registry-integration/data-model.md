# Data Model: Catalog Registry Integration

**Phase**: 1 — Design
**Branch**: `005-catalog-registry-integration`
**Spec**: [spec.md](spec.md) | **Research**: [research.md](research.md)

---

## New Types

### RegistryAPIResponse (raw decode, `RegistryClient.swift`)

Decodable structs that mirror the registry API JSON exactly. Used only inside `URLSessionRegistryClient` — never exposed beyond the client boundary.

```
RegistryAPIResponse
  servers: [RegistryAPIServerWrapper]
  metadata: RegistryAPIMetadata

RegistryAPIServerWrapper
  server: RegistryAPIServer
  _meta → meta: RegistryAPIMeta          (CodingKey: "_meta")

RegistryAPIServer
  name: String                            "io.github.Author/server-name"
  description: String
  version: String
  packages: [RegistryAPIPackage]?
  remotes: [RegistryAPIRemote]?
  repository: RegistryAPIRepository?

RegistryAPIPackage
  registryType: String                    "npm" | "pypi" | "oci"
  identifier: String
  version: String?
  environmentVariables: [RegistryAPIEnvVar]?
  transport: RegistryAPITransport?

RegistryAPITransport
  type: String                            "stdio"

RegistryAPIRemote
  type: String                            "streamable-http" | "sse"
  url: String
  headers: [RegistryAPIEnvVar]?

RegistryAPIEnvVar
  name: String
  description: String?
  isRequired: Bool?
  isSecret: Bool?
  format: String?
  value: String?                          header template value, e.g. "Bearer {api_key}"

RegistryAPIMeta
  official: RegistryAPIOfficialMeta       CodingKey: "io.modelcontextprotocol.registry/official"

RegistryAPIOfficialMeta
  isLatest: Bool
  status: String                          "active" | "deprecated"

RegistryAPIMetadata
  count: Int
  nextCursor: String?

RegistryAPIRepository
  url: String
  source: String
```

---

### RegistryEntry (app model, `RegistryEntry.swift`)

The app's in-memory representation of a server from the registry. Produced by transforming a `RegistryAPIServerWrapper` where `isLatest == true` and `isActionable == true`. `Codable` for cache persistence.

```
RegistryEntry: Identifiable, Equatable, Codable
  id: String                              = server.name (unique per server)
  displayName: String                     derived from id (see research Decision 5)
  description: String
  packageType: PackageType?               nil if HTTP-only
  packageIdentifier: String?              nil if HTTP-only
  remoteURL: String?                      nil if stdio-only
  remoteType: RemoteTransportType?        nil if stdio-only
  remoteHeaders: [RegistryEnvVar]         request headers for HTTP servers
  envVars: [RegistryEnvVar]               env vars for stdio packages
  repositoryURL: String?
  version: String

  — Computed —
  derivedCommand: String?                 npm→"npx", pypi→"uvx", oci→"docker"; nil if HTTP-only
  derivedArgs: [String]?                  npm→["-y", id], pypi/oci→[id]; nil if HTTP-only
  transportType: TransportType            .stdio | .http | .sse
  isActionable: Bool                      has (packageType+identifier) OR remoteURL
```

**Transformation rules** (pure static functions, unit-testable):
- `filterLatest(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]` — keep only `isLatest == true`
- `deduplicate(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]` — keep first occurrence per `server.name`
- `RegistryEntry.init?(raw: RegistryAPIServerWrapper)` — failable; returns nil if not actionable
- `deriveCommand(packageType: PackageType, identifier: String) -> (String, [String])` — pure, no side effects
- `displayName(from registryName: String) -> String` — pure, strips suffix noise, title-cases

---

### RegistryEnvVar (`RegistryEntry.swift`)

```
RegistryEnvVar: Equatable, Codable
  name: String
  description: String
  isRequired: Bool
  isSecret: Bool
```

---

### PackageType (`RegistryEntry.swift`)

```
enum PackageType: String, Codable
  case npm
  case pypi
  case oci
```

---

### RemoteTransportType (`RegistryEntry.swift`)

```
enum RemoteTransportType: String, Codable
  case streamableHTTP = "streamable-http"   maps to TransportType.http
  case sse                                  maps to TransportType.sse
```

---

### CategoryCacheState (`RegistryStore.swift`)

Per-category state for the category browser. Drives loading indicators and empty states in `CatalogView`.

```
enum CategoryCacheState: Equatable
  case uncached                            no data, never fetched
  case loading                             initial fetch in progress
  case loaded(fetchedAt: Date, entries: [RegistryEntry])
  case failed(message: String)             fetch failed, no prior cache
```

---

### SearchState (`RegistryStore.swift`)

Global live-search state.

```
enum SearchState: Equatable
  case idle                                no active search
  case searching                           request in flight
  case results([RegistryEntry])            live results from registry
  case localOnly([RegistryEntry])          offline fallback: cached entries matching query
  case empty                               registry returned 0 results
  case failed(message: String)
```

---

### RegistryCacheFile (cache persistence format, `RegistryStore.swift`)

JSON written to `~/Library/Application Support/mcp-inator/registry-cache.json`.

```
RegistryCacheFile: Codable
  version: Int                             1 for this implementation
  categories: [String: CategoryCacheEntry] keyed by CatalogCategory.rawValue

CategoryCacheEntry: Codable
  fetchedAt: Date
  entries: [RegistryEntry]
```

---

## Modified Types

### EnvVar (modified, `MCPServerConfig.swift`)

Add `isHint: Bool = false`. **Not added to `CodingKeys`** — never persisted to DB or agent config files. Set to `true` only by `MCPServerConfig.init(from: RegistryEntry)`.

```
struct EnvVar                              (existing)
  + var isHint: Bool = false               NEW — UI-only, not in CodingKeys
```

**Visual treatment in `EnvVarRow`**: when `envVar.isHint == true`, show a capsule badge reading "Suggested" and a help text "Verify variable names with the package's own documentation before saving."

---

### MCPServerConfig (modified, `MCPServerConfig.swift`)

Add a new convenience initializer from `RegistryEntry`:

```swift
extension MCPServerConfig {
    init(from entry: RegistryEntry) {
        // stdio path: use derivedCommand + derivedArgs
        // HTTP path: use remoteURL + remoteHeaders
        // All env vars and headers get isHint = true
    }
}
```

---

## Deleted Types

The following are removed as part of this feature:

| Type | File | Reason |
|------|------|--------|
| `CatalogEntry` | `CatalogEntry.swift` | Replaced by `RegistryEntry` |
| `CatalogEnvVar` | `CatalogEntry.swift` | Replaced by `RegistryEnvVar` |
| `CatalogMetadata` | `CatalogEntry.swift` | No equivalent in registry model |
| `Catalog` | `CatalogEntry.swift` | No equivalent in registry model |
| `CatalogStore` | `CatalogStore.swift` | Replaced by `RegistryStore` |
| `Catalog.supportedSchemaVersion` | `CatalogEntry.swift` | Not applicable |

`CatalogCategory` enum is **kept** — it's a UI concept (categories shown in `CatalogView`) independent of the data source.

**Bundle resource removed**: `Resources/catalog.json`

---

## State Transitions

### Category loading (per category)

```
uncached ──[app launched, network available]──► loading
         ──[app launched, cache exists]──────► loaded (from cache)

loading ──[fetch succeeded]──► loaded
        ──[fetch failed, no cache]──► failed
        ──[fetch failed, prior cache]──► loaded (cache retained)

loaded ──[background refresh triggered]──► loading (cache shown while refreshing)
       ──[background refresh succeeded]──► loaded (updated)
       ──[background refresh failed]────► loaded (stale cache retained, no error shown)
```

### Search state

```
idle ──[user types, query non-empty]──► searching
     ──[user clears text]────────────► idle (no state change needed)

searching ──[response received, results > 0]──► results
          ──[response received, results == 0]──► empty
          ──[URLError: offline]───────────────► localOnly (cached filter applied)
          ──[other error]──────────────────────► failed

results/localOnly/empty/failed ──[user clears text]──► idle
                               ──[user types again]──► searching
```
