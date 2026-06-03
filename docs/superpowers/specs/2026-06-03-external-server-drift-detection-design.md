# External Server Drift Detection — Design

**Issue:** #60  
**Date:** 2026-06-03  
**Status:** Approved

## Problem

When a server is added directly to an agent's config file outside of mcp-inator (e.g. by the agent's own UI or manual JSON editing), the app has no record of that key. `checkDrift` in `AgentAdapter` intentionally ignores unmanaged keys during pre-flight comparisons, so these externally-added servers are silently invisible in the app. There is no path for the user to pull them into the library without manually re-entering them.

## Goal

When `AgentListView` opens (or refreshes), detect any server key in the agent's config file that is not in the mcp-inator library and has not been previously dismissed. Surface a banner offering to import all such servers or leave them unmanaged permanently.

## Architecture

### Data Layer

**Migration007** — new `unmanaged_keys` table:

```sql
CREATE TABLE unmanaged_keys (
    agentId   INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    serverKey TEXT    NOT NULL,
    createdAt REAL    NOT NULL,
    PRIMARY KEY (agentId, serverKey)
)
```

This is a pure exclusion list. Once a key is dismissed it will never re-prompt. There is no undo; users who change their mind can add the server manually.

**`ConfigStore` — two new methods:**

```swift
func scanForExternalKeys(agent: AgentRecord, adapter: any AgentAdapter) throws -> [String]
func markUnmanaged(agentId: Int64, keys: [String]) throws
```

`scanForExternalKeys` reads the config file via `adapter.readConfigs`, calls the existing `categorizeImport` to classify each on-disk key, then filters to `.new` keys that are not already in `unmanaged_keys` for that agent. Returns the server keys that should prompt the user.

`markUnmanaged` inserts `(agentId, serverKey, now)` rows using `INSERT OR IGNORE` so repeated calls are safe.

### UI Layer

`AgentListView` gains:

```swift
@State private var externalKeys: [String] = []
```

`refreshEnabledSet()` is extended: after computing `onDisk`, it calls `store.scanForExternalKeys(agent:adapter:)` and assigns the result to `externalKeys`. If the scan throws, `externalKeys` is silently cleared — consistent with the existing file-read fallback in the same method.

A new `externalServersBanner` subview renders when `!externalKeys.isEmpty`, inserted at the top of the VStack (above `driftView` and other banners). It follows the existing `unavailableBanner` visual style — orange tint, `HStack` with icon, key list, and two action buttons:

- **Import All** — calls `categorizeImport` + `applyImportDecisions`, clears `externalKeys`, triggers `restartNotice`.
- **Leave Unmanaged** — calls `markUnmanaged(agentId:keys:)`, clears `externalKeys`. No restart notice needed.

Banner sketch:

```
┌─────────────────────────────────────────────────────────┐
│ ↓  New servers found in config file                     │
│    "github-mcp", "postgres-mcp"     [Import All]        │
│                                     [Leave Unmanaged]   │
└─────────────────────────────────────────────────────────┘
```

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Key already in library (exactMatch/conflict) | `categorizeImport` classifies as non-`.new`; not surfaced |
| `mcp-inator` self-key | `categorizeImport` already skips it |
| Import races with concurrent library add | `applyImportDecisions` upserts; no duplicate |
| File unreadable during scan | Scan throws → `externalKeys = []`; banner hidden |
| Agent unavailable | `refreshEnabledSet` returns early; scan never runs |
| Dismissed key reappears with new config | Stays suppressed; user adds manually if desired |

## Testing

- Unit test `scanForExternalKeys`: config has key A (in library), B (new), C (in `unmanaged_keys`) → returns `["B"]` only.
- Unit test `markUnmanaged`: calling twice with the same key does not throw.
- Unit test `refreshEnabledSet` when `scanForExternalKeys` throws (unreadable file): `externalKeys` is set to `[]` and no error propagates to the view.
- No new test infrastructure required; follows existing `ConfigStoreTests` and `FileBasedAdapterTests` patterns.

## Files Touched

| File | Change |
|---|---|
| `Store/Migrations/Migration007.swift` | New — creates `unmanaged_keys` table |
| `Store/ConfigStore.swift` | `scanForExternalKeys` + `markUnmanaged` methods; register Migration007 |
| `UI/AgentListView.swift` | `externalKeys` state; extend `refreshEnabledSet`; add `externalServersBanner` |
| `mcp-inatorTests/Unit/ConfigStoreTests.swift` | New test cases for scan + markUnmanaged |
