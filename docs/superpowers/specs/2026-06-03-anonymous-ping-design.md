# Anonymous Install & Daily-Active Ping — Design Spec

## Goal

Fire two silent, opt-in-free pings to the existing Cloud Run backend so the project maintainer can see how many installs exist and how many users are active each day — without collecting any PII.

## Background

The app already has opt-in anonymous usage sharing (`/report` endpoint, `UsageSharingService`). That feature requires user consent and reports which MCP server keys are in use. This feature is different: it tracks only app lifecycle events (first launch ever, and once-per-day activity), requires no consent, and collects no server or configuration data.

---

## Client-Side Architecture

### New file: `mcp-inator/Services/PingService.swift`

One public method: `firePingsIfNeeded()`. Called once from the app entry point alongside the existing `UsageSharingService.flushPendingIfNeeded()` call.

**Logic:**

1. Check `PingPreferences.hasLaunched` (Bool). If `false`, mark it `true` immediately (before the network call — prevents double-fire on failure), then enqueue a `first_launch` ping.
2. Check `PingPreferences.lastActiveDate` (String, `"yyyy-MM-dd"`). If it does not equal today's local calendar date, update it to today immediately, then enqueue a `daily_active` ping.
3. Fire all enqueued pings concurrently via `URLSession.shared`, 10-second timeout. Fire-and-forget — failures are silently discarded. No persistent retry queue.

**Reads from existing shared config:** `TelemetryConfig.serviceURL`, `TelemetryConfig.bearerToken` (both defined in `SharingPreferences.swift`).

### New namespace: `PingPreferences`

Enum with static computed properties backed by `UserDefaults.standard`:

| Key | Type | Purpose |
|-----|------|---------|
| `pingHasLaunched` | `Bool` | Set to `true` after first-launch ping is enqueued; never reset |
| `pingLastActiveDate` | `String` | `"yyyy-MM-dd"` of last daily-active ping; updated before firing |

---

## HTTP Contract

**Endpoint:** `POST /ping` (new route on existing Cloud Run service)

**Auth:** `Authorization: Bearer <token>` — same token as `/report`

**Request body:**
```json
{
  "schemaVersion": "1",
  "event": "first_launch",
  "appVersion": "0.5.3"
}
```

- `event`: `"first_launch"` or `"daily_active"`
- `appVersion`: `Bundle.main.infoDictionary["CFBundleShortVersionString"]` as String; falls back to `"unknown"` if missing
- `schemaVersion`: always `"1"`

**Success response:**
```json
{ "status": "ok" }
```

**Error responses:**
- `401` — missing or wrong bearer token
- `400` — `schemaVersion != "1"`, unrecognised `event`, or `appVersion` empty or > 32 chars
- `503` — Firestore error (client ignores; fire-and-forget)

---

## Backend Changes (`backend/main.go`)

New handler registered at `POST /ping`. Uses the same bearer-token auth middleware as `/report`.

**Validation:**
- Body size limit: 64 KB (consistent with `/report`)
- `schemaVersion` must equal `"1"`
- `event` must be `"first_launch"` or `"daily_active"`
- `appVersion` must be non-empty and ≤ 32 chars

**Firestore writes:**

For `first_launch` → collection `app_installs`, document ID = `appVersion`:
```
{ count: <incremented>, firstSeenAt: <set once>, lastSeenAt: <updated each time> }
```

For `daily_active` → collection `daily_active`, document ID = UTC date string `"YYYY-MM-DD"`:
```
{ count: <incremented>, date: "2026-06-03" }
```

Both use the existing create-or-increment pattern already in the codebase:
- Attempt `Create` (sets `firstSeenAt`/`date` once)
- On `AlreadyExists`: `Update` with `FieldValue.Increment(1)` and `lastSeenAt = now`

**Privacy:** handler must not log `r.RemoteAddr` or any IP-bearing headers (consistent with `/report`).

---

## Firestore Schema

### `app_installs/{appVersion}`
```
count:       int64      // incremented on each first_launch ping for this version
firstSeenAt: timestamp  // set on document creation; never updated
lastSeenAt:  timestamp  // updated on every ping
```

### `daily_active/{YYYY-MM-DD}`
```
count: int64   // incremented on each daily_active ping for this date
date:  string  // "2026-06-03"; set on creation
```

---

## Privacy Properties

- No IP addresses logged or stored
- No device identifiers
- No user identifiers
- `appVersion` is the app release version string only (e.g., `"0.5.3"`)
- Bearer token is a shared static secret in the compiled binary — same approach as `/report`; acceptable for anonymous aggregate counters
- No opt-in required; no UI changes

---

## What Is Not In Scope

- Retry queue for failed pings (fire-and-forget is sufficient for aggregate analytics)
- User-facing settings to disable pings
- Any dashboard or reporting UI
- Changes to the existing `/report` endpoint or opt-in flow
