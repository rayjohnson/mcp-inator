# Contract: Telemetry Payload (mcp-inator → Cloudflare Worker)

**Endpoint**: `POST https://<worker>.workers.dev/report`  
**Direction**: mcp-inator app → Cloudflare Worker  
**Content-Type**: `application/json`  
**Auth**: None (anonymous endpoint; no credentials sent or required)

---

## Request Schema

```json
{
  "schemaVersion": "1",
  "reportedAt": "2026-05-29T10:30:00Z",
  "sessionToken": "a8f3c2b1d4e5f6a7b8c9d0e1f2a3b4c5",
  "servers": [
    {
      "serverKey": "github",
      "command": "npx",
      "sanitizedArgs": ["-y", "@modelcontextprotocol/server-github"],
      "transportType": "stdio",
      "isEnabled": true,
      "envVarKeys": ["GITHUB_PERSONAL_ACCESS_TOKEN"],
      "userDescription": null,
      "isKnownCatalogEntry": true
    },
    {
      "serverKey": "my-internal-tool",
      "command": "[custom-command]",
      "sanitizedArgs": ["[path]", "--port", "8080"],
      "transportType": "stdio",
      "isEnabled": false,
      "envVarKeys": ["API_KEY", "BASE_URL"],
      "userDescription": "My team's internal data access server",
      "isKnownCatalogEntry": false
    }
  ]
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| `schemaVersion` | String `"1"`. |
| `reportedAt` | ISO 8601 client timestamp. |
| `sessionToken` | 32-character hex string. Random per submission. Discarded by Worker after aggregation. |
| `servers` | Non-empty array. User has already excluded any servers they toggled off in the review screen. |
| `command` | Known package manager (`npx`, `uvx`, `node`, `python`, `pip`, `docker`, `brew`) → included as-is. Any other string → `"[custom-command]"`. |
| `sanitizedArgs` | Any arg starting with `/`, `~`, `./`, `../` → replaced with `"[path]"`. Package names and flags preserved. |
| `envVarKeys` | Names only. No values under any circumstances. |
| `userDescription` | `null` unless user explicitly opts in per-server. |
| `isKnownCatalogEntry` | `false` servers are flagged by Worker as potential new catalog candidates. |

## Sanitization Applied Before Transmission

The app MUST apply these rules client-side before showing the review screen AND before transmitting:

1. `command`: if not in allowlist → `"[custom-command]"`
2. `args`: each arg → if starts with `/`, `~`, `./`, `../` → `"[path]"`
3. `envVarKeys`: strip values; include only key names
4. `userDescription`: include only if user toggled per-server opt-in to `true`

## Response Schema

```json
{
  "status": "ok",
  "accepted": 3
}
```

| Field | Notes |
|-------|-------|
| `status` | `"ok"` on success. |
| `accepted` | Number of server entries processed. |

On error: standard HTTP 4xx/5xx. The app retries up to 3 times with exponential backoff; after 3 failures silently drops the payload.

## Worker Behaviour

1. Parse payload; validate `schemaVersion`
2. For each server entry, increment `userCount` and `enabledCount` in the in-memory aggregation buffer (or directly update `usage.json` via GitHub Contents API)
3. Flag `isKnownCatalogEntry: false` entries for curator review (write to `candidate-submissions.json`)
4. Discard `sessionToken` — never persisted
5. Never log `reportedAt` with any network-layer identifier
