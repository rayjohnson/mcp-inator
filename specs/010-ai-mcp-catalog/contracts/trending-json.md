# Contract: trending.json

**File**: `rayjohnson/mcp-catalog/trending.json`  
**Updated by**: Weekly GitHub Action (`weekly-sentiment.yml`) — automated write, no PR required  
**Consumed by**: mcp-inator app (raw GitHub URL fetch)

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "1",
    "computedAt": "2026-05-29T00:00:00Z",
    "periodDays": 30,
    "subreddits": ["r/ClaudeAI", "r/mcp", "r/MachineLearning", "r/LocalLLaMA"]
  },
  "trending": {
    "https://github.com/modelcontextprotocol/servers": {
      "repositoryURL": "https://github.com/modelcontextprotocol/servers",
      "trendingScore": 78,
      "sentimentSummary": "Widely praised for breadth of coverage; users note the filesystem server requires careful path scoping.",
      "mentionCount": 34,
      "periodDays": 30,
      "computedAt": "2026-05-29T00:00:00Z"
    }
  }
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| Key (outer `trending` map) | Must equal `repositoryURL` value. |
| `trendingScore` | Integer 0–100. 0 = no signal; 100 = maximum observed velocity. |
| `sentimentSummary` | 1–2 sentences max. Plain English. Must be based on actual post content, not invented. |
| `mentionCount` | Non-negative integer. Posts + comments. Must be > 0 for entry to exist. |
| `periodDays` | Integer, typically 30. Matches metadata-level `periodDays`. |
| `computedAt` | ISO 8601. |

## Absent Entries

A server absent from `trending.json` has no trending score and no sentiment summary. The app MUST NOT show "No mentions found" — simply omit the trending section for that server.

## Trending Threshold

Servers with `trendingScore >= 70` (configurable in the app) appear in the dedicated "Trending" section at the top of the catalog. The threshold is a client-side filter — the file contains all scored servers regardless of threshold.

## Score Methodology

Computed by the weekly Action using this formula as guidance (exact weights are implementation detail):
- Base: `mentionCount` normalized against the highest-mention server in the period
- Velocity bonus: posts in the last 7 days weighted 2× vs posts in days 8–30
- Sentiment adjustment: Claude assigns ±10 points based on whether community posts are net positive/negative

The formula may evolve; the 0–100 contract is stable.
