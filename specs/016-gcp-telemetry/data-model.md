# Data Model: GCP Telemetry Backend

## Firestore Collections

### `server_usage` (Cloud — Firestore)

Stores aggregate anonymous usage counts per MCP server.

| Field         | Type      | Description |
|---------------|-----------|-------------|
| `count`       | int64     | Number of times this server key appeared in accepted reports. Atomically incremented — never decremented or reset. |
| `firstSeenAt` | timestamp | Timestamp of the first report that included this server key. |
| `lastSeenAt`  | timestamp | Timestamp of the most recent report that included this server key. |

**Document ID**: `serverKey` string (e.g., `github-mcp`, `filesystem`). Unknown keys (not in catalog) are accepted and tracked.

**Write pattern**: `FieldValue.increment(1)` on `count` + `lastSeenAt = now`. On first write, also set `firstSeenAt`.

**Read pattern**: Full collection scan once per weekly refresh run. No queries needed — all documents are read.

---

## App-Side Models (Swift)

### `UsageReport` (outbound payload)

Sent by `UsageSharingService` to `POST /report`.

| Field           | Type     | Description |
|-----------------|----------|-------------|
| `schemaVersion` | String   | Always `"1"` for current clients. |
| `serverKeys`    | [String] | Keys of opted-in, non-private, enabled servers included in this report. |

### `SanitizedServerEntry` (review screen)

One entry in `SharingReviewView` per server. Built from `MCPServerConfig`.

| Field          | Type     | Description |
|----------------|----------|-------------|
| `serverKey`    | String   | The server's identifier. |
| `command`      | String   | The command name (not full path — basename only). |
| `sanitizedArgs`| [String] | Args with filesystem path segments replaced with `<path>`. |
| `envVarKeys`   | [String] | Env var key names only. Values never included. |
| `isExcluded`   | Bool     | User-toggled per-server exclude on the review screen. |

### UserDefaults keys (sharing preferences)

| Key | Type | Description |
|-----|------|-------------|
| `sharingConsented` | Bool | True after user submits from review screen. |
| `sharingConsentShownAt` | Date? | When the prompt was last shown (nil = never). |
| `pendingUsageReport` | Data? | Queued report payload to retry on next launch. |
| `sharingExcludedKeys` | [String] | Server keys the user has permanently excluded from reports. |

---

## Service API Model

### `POST /report` request body

```json
{
  "schemaVersion": "1",
  "serverKeys": ["github-mcp", "filesystem"]
}
```

Validation rules:
- `schemaVersion` must be present and equal `"1"` — otherwise 400
- `serverKeys` must be a non-null array — empty array is accepted (accepted=0)
- Request body must be ≤ 64KB — otherwise 413
- Each key must be a non-empty string ≤ 256 chars — invalid keys are skipped, not rejected

### `POST /report` response body

```json
{ "status": "ok", "accepted": 2 }
```

`accepted` = count of keys that were actually incremented in Firestore.
