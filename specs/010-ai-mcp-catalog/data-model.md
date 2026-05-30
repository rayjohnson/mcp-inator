# Data Model: AI-Curated MCP Server Catalog

**Feature**: 010-ai-mcp-catalog | **Date**: 2026-05-29

---

## CatalogEntry

The primary catalog record. Stored in `servers.json` in the `rayjohnson/mcp-catalog` repo. Displayed in the mcp-inator catalog tab. The app maps this to the existing `RegistryEntry` model using a new initializer — all new fields are additive.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | String | yes | Unique stable identifier, e.g. `"github"`, `"stripe"` |
| displayName | String | yes | Human-readable name, e.g. `"GitHub"` |
| category | String | yes | One of: Code & Development, Productivity, Data & Analytics, Communication, Infrastructure, AI & LLMs, Web & Browser |
| shortDescription | String | yes | One sentence, no marketing language |
| curatorNote | String? | no | Why this server was chosen; gotchas to know before adding |
| transportType | String | yes | `"stdio"` or `"http"` |
| command | String | yes | Executable, e.g. `"npx"`, `"uvx"`, `"docker"` |
| args | [String] | yes | CLI arguments, e.g. `["-y", "@scope/package"]` |
| url | String? | no | Remote URL for http/sse transports |
| envVars | [EnvVarDefinition] | yes | May be empty array; env vars required to run the server |
| requiredArgs | [RequiredArgDefinition]? | no | Positional arguments the server requires |
| documentationURL | String? | no | Link to server docs |
| repositoryURL | String? | no | GitHub repo URL |
| isVerified | Bool | yes | `true` for well-tested, known-good entries |
| isFirstParty | Bool | yes | `true` if maintained by the company that owns the service (e.g. Stripe's own MCP server). Default `false` |
| alternativeTo | String? | no | `id` of the recommended server when this entry is a ranked alternative for the same service |
| serverKey | String | yes | Stable key used in mcp-inator config store, e.g. `"github"` |

**State transitions**: CatalogEntry is immutable after curator merge. Weekly refresh opens PRs with field updates; human review required before any change lands in `servers.json`.

---

## EnvVarDefinition

Embedded in `CatalogEntry.envVars`. Documents every environment variable the server requires or accepts.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| name | String | yes | Env var name, e.g. `"GITHUB_PERSONAL_ACCESS_TOKEN"` |
| description | String | yes | What this value is for, how to obtain it |
| isRequired | Bool | yes | Whether the server fails to start without it |
| isSensitive | Bool | yes | Whether it holds credentials/secrets that should be masked in UI |

---

## RequiredArgDefinition

Embedded in `CatalogEntry.requiredArgs`. Documents positional CLI arguments the server expects.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| name | String | yes | Argument name for display, e.g. `"repository-path"` |
| description | String | yes | What the argument represents |
| placeholder | String | yes | Placeholder shown in UI, e.g. `"/path/to/repo"` |
| isRequired | Bool | yes | Whether the arg is mandatory |

---

## ServerMetrics

Stored in `stats.json` (auto-updated weekly). Keyed by `serverKey`. Consolidates all computed per-server signals — GitHub stats, Reddit sentiment, and usage counts. Written in two passes each Monday: refresh job writes GitHub stats + usage counts at 2am; sentiment job patches sentiment fields at 4am.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| serverKey | String | yes | Primary key — matches `CatalogEntry.serverKey` |
| repositoryURL | String? | no | GitHub repo URL. May be absent for servers without a public repo |
| starCount | Int? | no | Current GitHub star count |
| forkCount | Int? | no | Current GitHub fork count |
| lastCommitDate | String (ISO 8601)? | no | Date of most recent commit to default branch |
| openIssueCount | Int? | no | Open issue count |
| isArchived | Bool | yes | Whether the GitHub repo is archived. `true` triggers a drift PR |
| githubFetchedAt | String (ISO 8601) | yes | When GitHub API was last called for this entry |
| isTrending | Bool | yes | Set by sentiment job based on score distribution analysis. `true` = appears in app's Trending section. Default `false` |
| trendingScore | Int (0–100)? | no | Absent if no Reddit mentions in lookback window. Used for ordering within the Trending section, not for determining membership |
| sentimentSummary | String? | no | One-sentence community sentiment. Absent (not shown) if no mentions |
| mentionCount | Int? | no | Reddit posts/comments in the lookback window. Absent if 0 |
| periodDays | Int? | no | Lookback window in days (typically 30) |
| sentimentComputedAt | String (ISO 8601)? | no | When sentiment was last computed |
| userCount | Int? | no | Distinct contributors who included this server in their most recent weekly report |
| enabledCount | Int? | no | Of `userCount`, how many reported the server as currently enabled |
| weeklyActiveCount | Int? | no | Reports in the past 7 days that include this server |
| usageAggregatedAt | String (ISO 8601)? | no | When usage counts were last folded in from `usage.json` |

**App behavior**: All optional fields degrade gracefully — no `trendingScore` → no Trending badge; no `userCount` → no "used by N users" label.

---

## UsageReport

Payload sent from mcp-inator to the Cloudflare Worker endpoint (never stored as-is). Represents one user's anonymized opted-in server snapshot. The Worker accumulates these into the internal `usage.json` file; the weekly refresh job folds counts into `stats.json`.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| reportedAt | String (ISO 8601) | yes | Client-side timestamp |
| servers | [SanitizedServerEntry] | yes | Opted-in servers after client-side sanitization |

**Privacy invariants**: No user identifier, no IP, no hostname, no UUID. The session token (random, per-submission) is discarded by the Worker after the report is counted.

---

## SanitizedServerEntry

Embedded in `UsageReport.servers`. One server from the user's library after sanitization rules applied (Decision 6 in research.md).

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| serverKey | String | yes | From `MCPServerConfig.serverKey` |
| command | String | yes | Known package manager commands (`npx`, `uvx`, `node`, `python`, `pip`, `docker`, `brew`) included as-is; other values replaced with `[custom-command]` |
| sanitizedArgs | [String] | yes | Filesystem paths replaced with `[path]`; package names preserved |
| transportType | String | yes | `"stdio"` or `"http"` |
| isEnabled | Bool | yes | Whether the server is currently enabled for any agent |
| envVarKeys | [String] | yes | Env var names only — no values |
| userDescription | String? | no | Only included if user explicitly opts in to sharing their description |
| isKnownCatalogEntry | Bool | yes | `false` = potential new catalog candidate |

---

## Relationships

```
CatalogEntry 1──* EnvVarDefinition        (envVars array)
CatalogEntry 1──* RequiredArgDefinition   (requiredArgs array)
CatalogEntry ──── ServerMetrics           (via serverKey)
CatalogEntry ──── CatalogEntry            (alternativeTo: self-referential)
UsageReport  1──* SanitizedServerEntry    (servers array, client-side only)
```

---

## App-Side Merge Model

The mcp-inator app fetches **two files** in parallel and merges them into a display model:

```
servers.json  →  [CatalogEntry]    (curated catalog, human-reviewed)
stats.json    →  [ServerMetrics]   (all computed signals, keyed by serverKey)
```

The merged view model attaches ServerMetrics to each CatalogEntry by `serverKey`. All ServerMetrics fields are optional — absent fields degrade gracefully to nil/hidden in the UI.

The internal `usage.json` (Cloudflare Worker accumulator) is never fetched by the app. Usage counts reach the app only after the weekly refresh job folds them into `stats.json`.
