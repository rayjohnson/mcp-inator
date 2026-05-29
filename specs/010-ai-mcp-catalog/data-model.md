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

## ServerStats

Stored in `stats.json` (auto-updated weekly by GitHub Action). Keyed by `repositoryURL` to decouple from `servers.json` evolution.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| repositoryURL | String | yes | GitHub repo URL — foreign key into CatalogEntry |
| starCount | Int | yes | Current GitHub star count |
| forkCount | Int | yes | Current GitHub fork count |
| lastCommitDate | String (ISO 8601) | yes | Date of most recent commit to default branch |
| openIssueCount | Int | yes | Open issue count |
| isArchived | Bool | yes | Whether the GitHub repo is archived |
| fetchedAt | String (ISO 8601) | yes | When this record was fetched |

---

## TrendingEntry

Stored in `trending.json` (auto-updated weekly by GitHub Action). Only present for servers with Reddit activity.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| repositoryURL | String | yes | GitHub repo URL — foreign key into CatalogEntry |
| trendingScore | Int (0–100) | yes | Composite score: mention velocity × recency × sentiment |
| sentimentSummary | String | yes | One-sentence community sentiment, e.g. `"Widely praised for easy setup; occasional auth issues on older versions"` |
| mentionCount | Int | yes | Number of Reddit posts/comments in the lookback window |
| periodDays | Int | yes | Lookback window in days (typically 30) |
| computedAt | String (ISO 8601) | yes | When this entry was computed |

**Invariant**: If `mentionCount` is 0 the entry is omitted entirely (absent ≠ "no mentions found").

---

## UsageReport

Payload sent from mcp-inator to the Cloudflare Worker endpoint (never stored as-is). Represents one user's anonymized opted-in server snapshot.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| reportedAt | String (ISO 8601) | yes | Client-side timestamp |
| servers | [SanitizedServerEntry] | yes | Opted-in servers after client-side sanitization |

**Privacy invariants**: No user identifier, no IP, no hostname, no UUID. The session token (random, per-submission) is discarded by the Worker after aggregation.

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

## UsageStats

Stored in `usage.json` in `rayjohnson/mcp-catalog`. Updated weekly by aggregation job. Displayed in mcp-inator as "used by N mcp-inator users".

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| serverKey | String | yes | Matches `CatalogEntry.serverKey` (or discovered key) |
| userCount | Int | yes | Distinct contributors who included this server in their most recent report |
| enabledCount | Int | yes | Of those, how many have it currently enabled |
| weeklyActiveCount | Int | yes | Submissions in the past 7 days that include this server |
| lastAggregatedAt | String (ISO 8601) | yes | When this row was last computed |

---

## Relationships

```
CatalogEntry 1──* EnvVarDefinition        (envVars array)
CatalogEntry 1──* RequiredArgDefinition   (requiredArgs array)
CatalogEntry ──── ServerStats             (via repositoryURL)
CatalogEntry ──── TrendingEntry           (via repositoryURL)
CatalogEntry ──── UsageStats              (via serverKey)
CatalogEntry ──── CatalogEntry            (alternativeTo: self-referential)
UsageReport  1──* SanitizedServerEntry    (servers array, client-side only)
```

---

## App-Side Merge Model

The mcp-inator app fetches three files in parallel and merges them into a display model:

```
servers.json  →  [CatalogEntry]
stats.json    →  [ServerStats]    (keyed by repositoryURL)
trending.json →  [TrendingEntry]  (keyed by repositoryURL)
usage.json    →  [UsageStats]     (keyed by serverKey)
```

The merged view model attaches stats/trending/usage to each CatalogEntry by key. Fields absent in stats/trending/usage degrade gracefully to `nil`/hidden in the UI — no entry becomes unrenderable due to missing supplementary data.
