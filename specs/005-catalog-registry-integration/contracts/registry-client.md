# Contract: RegistryClient Protocol

**Type**: Internal testability seam
**File**: `mcp-inator/Services/RegistryClient.swift`

---

## Purpose

`RegistryClient` is the boundary between `RegistryStore` and the network. Every network call in this feature routes through this protocol. Tests inject a stub implementation; production uses `URLSessionRegistryClient`.

This is the primary testability seam for the feature — by controlling what the client returns, tests can exercise every state transition in `RegistryStore` without network access.

---

## Protocol Definition

```swift
protocol RegistryClient: Sendable {
    /// Search the MCP registry. Returns entries filtered to isLatest: true and
    /// mapped to the app model. Never returns non-actionable entries.
    func search(query: String, pageSize: Int) async throws -> [RegistryEntry]
}
```

**Preconditions**: `query` is non-empty. `pageSize` is 1–100.

**Postconditions**: All returned entries have `isActionable == true` and `isLatest == true` (enforced by the production implementation, relied upon by callers).

**Error behavior**:
- Throws `URLError` for network failures (callers check `.code` to distinguish offline from other errors)
- Throws `DecodingError` if the registry API response cannot be decoded

---

## Production Implementation: URLSessionRegistryClient

```swift
struct URLSessionRegistryClient: RegistryClient {
    init(session: URLSession = .shared)
    
    func search(query: String, pageSize: Int = 100) async throws -> [RegistryEntry]
}
```

**Behavior**:
1. Build URL: `https://registry.modelcontextprotocol.io/v0/servers?search=<q>&pageSize=<n>`
2. Fetch via URLSession
3. Decode `RegistryAPIResponse`
4. Apply `filterLatest` + `deduplicate` (pure functions, tested independently)
5. Map each result to `RegistryEntry` via failable init, dropping nil results
6. Return resulting array (may be empty)

---

## Test Stub Pattern

```swift
struct StubRegistryClient: RegistryClient {
    var result: Result<[RegistryEntry], Error>
    
    func search(query: String, pageSize: Int) async throws -> [RegistryEntry] {
        try result.get()
    }
}
```

Tests set `result` to `.success([...])` for happy-path tests, or `.failure(URLError(.notConnectedToInternet))` for offline tests.

---

## Transformation Functions (pure, testable separately)

These free functions live alongside `URLSessionRegistryClient` in `RegistryClient.swift`. They take raw API types as input, making them independently testable with fixture JSON.

```swift
func filterLatest(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]
func deduplicate(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]
```

`RegistryEntry.init?(raw: RegistryAPIServerWrapper)` — failable initializer; returns `nil` if neither actionable package nor remote URL exists. Tested via `RegistryEntryTests`.
