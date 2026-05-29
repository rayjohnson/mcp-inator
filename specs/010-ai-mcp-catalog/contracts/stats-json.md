# Contract: stats.json

**File**: `rayjohnson/mcp-catalog/stats.json`  
**Updated by**: Weekly GitHub Action (`weekly-refresh.yml`) — automated write, no PR required  
**Consumed by**: mcp-inator app (raw GitHub URL fetch)

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "1",
    "computedAt": "2026-05-29T00:00:00Z"
  },
  "stats": {
    "https://github.com/modelcontextprotocol/servers": {
      "repositoryURL": "https://github.com/modelcontextprotocol/servers",
      "starCount": 12450,
      "forkCount": 880,
      "lastCommitDate": "2026-05-28T14:22:00Z",
      "openIssueCount": 143,
      "isArchived": false,
      "fetchedAt": "2026-05-29T00:00:00Z"
    }
  }
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| Key (outer `stats` map) | Must equal `repositoryURL` value. |
| `starCount` | Non-negative integer. |
| `forkCount` | Non-negative integer. |
| `lastCommitDate` | ISO 8601. May be absent if GitHub API cannot return it (repo with no commits). |
| `openIssueCount` | Non-negative integer. |
| `isArchived` | Boolean. When `true`, the weekly refresh also opens a PR flagging the catalog entry for removal. |
| `fetchedAt` | ISO 8601. Set by the Action at the time of the GitHub API call. |

## Missing Entries

If a catalog entry's `repositoryURL` is absent from `stats.json`, the app renders without GitHub stats (no star count, no recency indicator). This is not an error state — it means the entry hasn't been through a weekly refresh yet.

## Update Semantics

The weekly refresh Action overwrites the entire `stats.json` file. It does not merge — it rebuilds from scratch. This means stale entries for removed catalog servers are automatically dropped on the next refresh.
