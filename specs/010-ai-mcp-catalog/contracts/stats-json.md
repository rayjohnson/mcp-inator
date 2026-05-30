# Contract: stats.json

**File**: `rayjohnson/mcp-catalog/stats.json`  
**Updated by**: Weekly GitHub Action (`weekly-refresh.yml`) — automated write, no PR required. Refresh runs at 2am UTC Monday; sentiment update runs at 4am UTC Monday (updates sentiment fields only); usage counts folded in at end of refresh run.  
**Consumed by**: mcp-inator app (raw GitHub URL fetch) — one of the two app-facing catalog files.

This file consolidates all computed per-server signals. The app only needs `servers.json` and this file.

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "2",
    "computedAt": "2026-05-29T00:00:00Z"
  },
  "servers": {
    "github": {
      "serverKey": "github",
      "repositoryURL": "https://github.com/modelcontextprotocol/servers",

      "starCount": 12450,
      "forkCount": 880,
      "lastCommitDate": "2026-05-28T14:22:00Z",
      "openIssueCount": 143,
      "isArchived": false,
      "githubFetchedAt": "2026-05-29T02:00:00Z",

      "trendingScore": 78,
      "sentimentSummary": "Widely praised for breadth of coverage; users note the filesystem server requires careful path scoping.",
      "mentionCount": 34,
      "periodDays": 30,
      "sentimentComputedAt": "2026-05-29T04:00:00Z",

      "userCount": 98,
      "enabledCount": 71,
      "weeklyActiveCount": 45,
      "usageAggregatedAt": "2026-05-29T02:30:00Z"
    }
  }
}
```

---

## Field Rules

### GitHub Stats (written by weekly-refresh.yml)

| Field | Constraint |
|-------|-----------|
| `serverKey` | Matches `CatalogEntry.serverKey` — primary key for this file. |
| `repositoryURL` | GitHub repo URL. May be absent for servers without a public repo. |
| `starCount` | Non-negative integer. |
| `forkCount` | Non-negative integer. |
| `lastCommitDate` | ISO 8601. Absent if repo has no commits. |
| `openIssueCount` | Non-negative integer. |
| `isArchived` | Boolean. `true` triggers a drift PR from the refresh workflow. |
| `githubFetchedAt` | ISO 8601. Timestamp of the GitHub API call. |

### Sentiment / Trending (written by weekly-sentiment.yml, 2 hours after refresh)

| Field | Constraint |
|-------|-----------|
| `isTrending` | Boolean. Set by the sentiment job based on score distribution analysis (e.g. top N% that week). The app renders this flag directly — no threshold logic in the app. Defaults to `false`; absent = `false`. |
| `trendingScore` | Integer 0–100. Absent if no Reddit mentions in the lookback window. Used for ordering within the Trending section, not for determining membership. |
| `sentimentSummary` | 1–2 sentences. Absent if no mentions. MUST NOT be shown as "No mentions found" — simply omit. |
| `mentionCount` | Non-negative integer. Absent (not 0) if no mentions. |
| `periodDays` | Integer, typically 30. |
| `sentimentComputedAt` | ISO 8601. |

Servers with no Reddit activity have all sentiment fields absent and `isTrending: false`. The sentiment job reads the existing entry and patches only the sentiment fields, preserving GitHub stats written earlier in the same Monday run.

### Usage Counts (folded in by weekly-refresh.yml from internal usage.json)

| Field | Constraint |
|-------|-----------|
| `userCount` | Distinct contributors who included this server in their most recent weekly report. NOT cumulative all-time. |
| `enabledCount` | Of `userCount`, how many reported the server as currently enabled. |
| `weeklyActiveCount` | Reports in the past 7 days that include this server. |
| `usageAggregatedAt` | ISO 8601. |

## Key Design Notes

- **Keyed by `serverKey`** (not `repositoryURL`) so servers without a public GitHub repo still get usage counts.
- **All fields optional at read time.** The app degrades gracefully: no `trendingScore` → no Trending badge; no `userCount` → no "used by N users" label.
- **Trending threshold**: app shows Trending section for entries with `trendingScore >= 70` (developer-controlled constant, not a user setting).
- **Two writes per Monday**: refresh writes GitHub stats + usage at 2am; sentiment patches sentiment fields at 4am. The sentiment script reads the current file before writing to avoid overwriting GitHub stats.

## Missing Entries

A catalog entry absent from `stats.json` renders without any computed signals. This is not an error state — it means the entry hasn't completed a weekly cycle yet.
