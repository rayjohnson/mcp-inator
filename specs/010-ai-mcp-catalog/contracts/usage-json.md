# Contract: usage.json

**File**: `rayjohnson/mcp-catalog/usage.json`  
**Updated by**: Weekly aggregation job (Cloudflare Worker cron or GitHub Action) — automated write via GitHub Contents API  
**Consumed by**: mcp-inator app (raw GitHub URL fetch)

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "1",
    "lastAggregatedAt": "2026-05-29T00:00:00Z",
    "windowDays": 7,
    "contributorCount": 142
  },
  "usage": {
    "github": {
      "serverKey": "github",
      "userCount": 98,
      "enabledCount": 71,
      "weeklyActiveCount": 45,
      "lastAggregatedAt": "2026-05-29T00:00:00Z"
    }
  }
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| Key (outer `usage` map) | Must equal `serverKey` value. |
| `userCount` | Distinct contributors who included this server in their most recent weekly report. NOT cumulative all-time. |
| `enabledCount` | Of `userCount`, how many reported the server as currently enabled. |
| `weeklyActiveCount` | Reports in the past `windowDays` that include this server. |
| `lastAggregatedAt` | ISO 8601. |
| metadata `contributorCount` | Total distinct contributors in this aggregation window. |

## Privacy Invariants

- No user identifiers appear in this file. All counts are aggregates.
- The session token sent with usage reports is discarded by the Worker after the report is counted. It is never written to `usage.json`.
- IP addresses are never logged by the Worker.

## Display in App

The app displays `userCount` as "used by N mcp-inator users" on the catalog entry detail view. If `userCount` is 0 or absent, no usage count is shown (not "0 users").
