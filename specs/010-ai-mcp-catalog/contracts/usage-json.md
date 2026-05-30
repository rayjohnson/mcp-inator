# Contract: usage.json — Internal Worker Accumulator

**File**: `rayjohnson/mcp-catalog/usage.json`  
**Updated by**: Cloudflare Worker on each POST `/report` request (real-time)  
**Consumed by**: Weekly refresh job (`weekly-refresh.yml`) — folds counts into `stats.json`  
**NOT fetched by the app** — this is an internal pipeline file only.

---

## Purpose

The Cloudflare Worker accumulates per-server usage counts here in real-time. The weekly refresh job reads this file at the end of its run and folds the counts into `stats.json` (the app-facing file). This separation means:
- The Worker makes small, frequent writes to a lightweight accumulator file
- The app only downloads `servers.json` + `stats.json` (two files, not three or four)
- Usage counts update weekly in the app (aligned with the other metrics cadence)

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "1",
    "lastUpdatedAt": "2026-05-29T10:30:00Z",
    "windowDays": 7
  },
  "usage": {
    "github": {
      "serverKey": "github",
      "userCount": 98,
      "enabledCount": 71,
      "weeklyActiveCount": 45,
      "lastUpdatedAt": "2026-05-29T10:30:00Z"
    }
  }
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| Key (outer `usage` map) | Must equal `serverKey`. |
| `userCount` | Distinct contributors who included this server in their most recent report in the current window. |
| `enabledCount` | Of `userCount`, how many reported the server as currently enabled. |
| `weeklyActiveCount` | Reports received in the past `windowDays` days that include this server. |
| `lastUpdatedAt` | ISO 8601. Set by Worker on each write. |

## Privacy Invariants

- No user identifiers, IPs, or session tokens ever written here.
- The session token sent in each usage report is discarded by the Worker after the report is counted.
- This file contains only aggregate counts.

## Fold-In Behaviour (weekly-refresh.yml)

At the end of the weekly refresh run, `refresh.py` reads `usage.json` and writes `userCount`, `enabledCount`, `weeklyActiveCount`, and `usageAggregatedAt` fields into the corresponding server entries in `stats.json`. The `usage.json` file is then reset (cleared) for the next weekly window.
