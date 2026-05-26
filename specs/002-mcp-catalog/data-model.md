# Data Model: MCP Server Catalog

**Branch**: `002-mcp-catalog` | **Phase**: 1

---

## Entities

### CatalogEntry

Represents one known MCP server in the curated catalog. Read-only reference data; never written by the user.

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `String` | ✓ | Stable unique key; registry reverse-DNS name (e.g. `io.github.modelcontextprotocol/server-github`) |
| `displayName` | `String` | ✓ | Human-readable name shown in UI (e.g. "GitHub MCP") |
| `category` | `CatalogCategory` | ✓ | Enum; curated by mcp-inator maintainers |
| `shortDescription` | `String` | ✓ | 1–2 sentence description; shown in list row and detail |
| `transportType` | `TransportType` | ✓ | Reuses existing enum: `.stdio`, `.http`, `.sse` |
| `command` | `String` | stdio only | Runtime hint: `npx`, `uvx`, `docker`, etc. |
| `args` | `[String]` | stdio only | Package identifier + any fixed args (e.g. `["@modelcontextprotocol/server-github"]`) |
| `url` | `String` | http/sse only | Remote endpoint URL |
| `envVars` | `[CatalogEnvVar]` | ✗ | Required/optional environment variables |
| `documentationURL` | `String?` | ✗ | Docs or website link |
| `repositoryURL` | `String?` | ✗ | Source repo URL |
| `isVerified` | `Bool` | ✓ | `true` = curated by mcp-inator maintainers; `false` = community-sourced |
| `serverKey` | `String` | ✓ | Pre-computed from `displayName`; used to detect "already in library" |

**Validation**: `id` must be unique within the catalog. `command` required when `transportType == .stdio`. `url` required when `transportType == .http` or `.sse`.

**Relationship to library**: `CatalogEntry.serverKey` is compared against `MCPServerConfig.serverKey` to show "Already in library" indicators. No foreign key — the catalog is not stored in GRDB.

---

### CatalogEnvVar

One environment variable required (or optional) by a catalog entry.

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | `String` | ✓ | Env var key name (e.g. `GITHUB_TOKEN`) |
| `description` | `String` | ✓ | Human-readable explanation of what this value should be |
| `isRequired` | `Bool` | ✓ | Whether the server will fail without it |
| `isSensitive` | `Bool` | ✓ | Maps to `MCPServerConfig.EnvVar.isSensitive` on add-to-library |
| `defaultValue` | `String?` | ✗ | Pre-fill value if a safe default exists |

---

### CatalogCategory (enum)

| Case | Raw value | Description |
|---|---|---|
| `codeAndDevelopment` | `"Code & Development"` | Git, CI, IDEs, code search |
| `productivity` | `"Productivity"` | Notes, tasks, calendars |
| `dataAndAnalytics` | `"Data & Analytics"` | Databases, BI, spreadsheets |
| `communication` | `"Communication"` | Slack, email, messaging |
| `infrastructure` | `"Infrastructure"` | Cloud, containers, monitoring |
| `aiAndLLMs` | `"AI & LLMs"` | AI APIs, model providers |
| `webAndBrowser` | `"Web & Browser"` | Web scraping, browser control |

---

### CatalogMetadata

Tracks catalog-level state; stored alongside entries in the JSON files.

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | `String` | Catalog format version (e.g. `"1"`) — bump on breaking changes |
| `bundledAt` | `Date` | ISO-8601; set at app build time for the bundle copy |
| `lastRefreshedAt` | `Date?` | ISO-8601; set on successful remote refresh; `nil` in bundle copy |
| `remoteEtag` | `String?` | Last ETag from remote; persisted in `UserDefaults` (not in JSON) |
| `entryCount` | `Int` | Convenience count; redundant with `entries.count` but useful for logging |

---

### Catalog (root JSON structure)

Top-level container for the catalog JSON files (both bundle and App Support).

```
Catalog
├── metadata: CatalogMetadata
└── entries: [CatalogEntry]
```

---

## Storage Layout

```
App Bundle (read-only):
  mcp-inator.app/Contents/Resources/catalog.json

App Support (writable, preferred if present):
  ~/Library/Application Support/mcp-inator/catalog.json

UserDefaults keys:
  catalogETag        String?   Last ETag from successful remote GET
```

---

## MCPServerConfig Initialisation from CatalogEntry

When the user taps "Add to Library", `CatalogEntry` is converted to a pre-filled `MCPServerConfig`:

| CatalogEntry field | MCPServerConfig field |
|---|---|
| `displayName` | `displayName` |
| `serverKey` | `serverKey` |
| `transportType` | `transportType` |
| `command` | `command` |
| `args` | `args` |
| `url` | `url` |
| `envVars[].name` | `envVars[].key` |
| `envVars[].defaultValue ?? ""` | `envVars[].value` |
| `envVars[].isSensitive` | `envVars[].isSensitive` |
| _(not in config model)_ | `notes = ""` |

The resulting `MCPServerConfig` is passed to `AddEditConfigView(prefill:)`. No `uuid` or `id` is set — GRDB assigns those on save.

---

## No GRDB Migration Required

The catalog is stored entirely as JSON files. No new database tables, columns, or migrations are needed for this feature.
