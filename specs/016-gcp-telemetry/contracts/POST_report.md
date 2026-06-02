# Contract: POST /report

**Endpoint**: `POST /report`  
**Service**: mcp-inator telemetry backend (Cloud Run)  
**Auth**: `Authorization: Bearer <TELEMETRY_BEARER_TOKEN>` (static shared token, same for all app users)  
**Content-Type**: `application/json`  
**Max body size**: 64KB

---

## Request

```json
{
  "schemaVersion": "1",
  "serverKeys": ["github-mcp", "filesystem", "my-server"]
}
```

| Field           | Type     | Required | Constraints |
|-----------------|----------|----------|-------------|
| `schemaVersion` | string   | Yes      | Must equal `"1"`. Any other value → 400. |
| `serverKeys`    | string[] | Yes      | Non-null array. Empty array accepted. Each key ≤ 256 chars, non-empty string. Invalid keys are skipped (not rejected). |

---

## Responses

### 200 OK — Report accepted

```json
{ "status": "ok", "accepted": 3 }
```

`accepted` = count of server keys that were incremented in Firestore. May be less than `serverKeys.length` if some keys were malformed and skipped.

### 400 Bad Request — Invalid payload

```json
{ "status": "error", "message": "missing or invalid schemaVersion" }
```

Returned when `schemaVersion` is absent or not `"1"`, or when the request body is not valid JSON.

### 401 Unauthorized — Missing or invalid token

```json
{ "status": "error", "message": "unauthorized" }
```

Returned when the `Authorization` header is absent or the bearer token does not match.

### 413 Request Entity Too Large

```json
{ "status": "error", "message": "request too large" }
```

Returned when the request body exceeds 64KB.

### 503 Service Unavailable — Storage error

```json
{ "status": "error", "message": "storage unavailable, please retry" }
```

Returned when Firestore is unreachable. App should retry with exponential backoff.

---

## Privacy Guarantees

- Client IP is not logged, stored, or forwarded.
- No session identifiers, device fingerprints, or user identifiers are accepted or stored.
- The service discards all HTTP headers except `Content-Type` and `Authorization`.

---

## Performance Target

- p95 response time ≤ 500ms under normal load.
- Scale-to-zero is acceptable; cold start latency is not included in the p95 target.
