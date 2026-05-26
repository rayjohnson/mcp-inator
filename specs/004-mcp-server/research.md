# Research: Built-in MCP Server

## Decision 1: Use hand-rolled JSON-RPC vs. official Swift SDK

**Decision**: Hand-roll the MCP protocol (JSON-RPC 2.0 + newline-delimited framing).

**Rationale**: The official Swift SDK (`modelcontextprotocol/swift-sdk`) requires **Swift 6.0 / Xcode 16+**. mcp-inator targets Swift 5.9. Adding the SDK would force a language version upgrade, which is a larger change than warranted for a small subset of the protocol. The MCP stdio protocol is genuinely simple: newline-delimited JSON, three-phase lifecycle, two request types. A ~200-line hand-rolled implementation is maintainable and avoids the dependency.

**Alternatives considered**:
- Use the official SDK: blocked by Swift 6.0 requirement.
- Use a generic JSON-RPC library: no Swift 5.9-compatible option found with MCP-specific semantics; would still require writing tool dispatch layer.

---

## Decision 2: Entry point — `main.swift` vs. separate Xcode target

**Decision**: Remove `@main` from `mcp_inatorApp`; add `main.swift` with a two-branch entry point.

```swift
// mcp-inator/App/main.swift
if CommandLine.arguments.contains("--mcp-server") {
    MCPServer().run()   // exits when stdin closes
} else {
    mcp_inatorApp.main()
}
```

**Rationale**: `@main` and `main.swift` are mutually exclusive in Swift. The two-branch `main.swift` pattern is the standard approach (used by Xcode itself, swift-argument-parser tools). No `project.yml` changes needed — the existing `sources: - mcp-inator` glob auto-discovers new `.swift` files. The server exits before `NSApplicationMain` ever runs, so no AppKit/window-server state is established in server mode.

**Alternatives considered**:
- Separate `tool` target: requires listing shared source files in two targets and keeping them in sync; useful if different entitlements are needed, but not needed here.
- Swift Package for shared code: significant restructuring overhead; not warranted at current project size.

---

## Decision 3: MCP protocol version to advertise

**Decision**: Advertise `2024-11-05` (the stable release from Nov 2024).

**Rationale**: This is the version supported by Claude Code's MCP client and is widely deployed. The newer `2025-06-18` spec adds output schemas, audio content, and elicitation — none of which we need. Advertising an older version the client knows is safer than advertising a newer version the client may reject.

**Alternatives considered**:
- `2025-06-18`: Most recent; adds features not needed; some clients may not yet support it.
- `2025-11-25`: Used by the official Swift SDK; not yet widely deployed in MCP clients.

---

## Decision 4: Direct DB access vs. IPC to running app

**Decision**: Direct SQLite access via GRDB — no IPC to the running app instance.

**Rationale**: GRDB operates in WAL mode by default, which allows concurrent readers and one writer. Two processes (app + MCP server) can safely read simultaneously; write contention is handled by GRDB's retry semantics. No IPC plumbing (XPC, Unix domain sockets) is needed, keeping the implementation simple and ensuring the server works even when the app is not running.

**Alternatives considered**:
- XPC to running app: would ensure serialized DB access but requires app to be running; adds ~200 lines of XPC boilerplate and an entitlement.
- Unix domain socket: same complexity problem as XPC, less type-safe.

---

## Decision 5: mcp-inator self-entry command path

**Decision**: The `command` field stored in the DB for the mcp-inator self-entry is a placeholder (`""`). At `enable_server` time, `MCPTools` resolves `Bundle.main.executableURL.path` and passes it directly to the adapter.

**Rationale**: Storing the bundle path permanently would break after app relocation (user moves to `/Applications`, updates via Sparkle, etc.). Resolving at write time ensures correctness. The `--mcp-server` mode also runs from the bundle, so `Bundle.main.executableURL` is always correct.

**Alternatives considered**:
- Store the resolved path and update it on every launch: works but adds a migration-like pattern and a DB write on every startup.
- Use a symlink in `/usr/local/bin`: requires extra install step; breaks if app is moved.

---

## MCP Wire Format Summary (for implementers)

- Framing: one JSON object per line, `\n` terminated, UTF-8.
- Server writes to stdout, reads from stdin. Stderr is safe for logging.
- Lifecycle: `initialize` (request/response) → `notifications/initialized` (no response) → normal operation.
- Server MUST NOT send requests until after `notifications/initialized` is received.
- Tool call errors: use `result.isError: true` for business logic failures; use `error` field only for protocol-level failures (parse, invalid request, method not found, invalid params).
- Ping (`method: "ping"`) must be handled: respond with `result: {}`.
- Unknown methods: respond with `error.code: -32601`.
- Missing required params: respond with `error.code: -32602`.
- Unknown tool name in `tools/call`: this is debated in the spec; use `result.isError: true` with a clear message (aligns with tool-error convention, not protocol error).

---

## JSONValue implementation approach

Swift's `Codable` system requires knowing the concrete type at decode time. To handle arbitrary JSON params/args, we implement a `JSONValue` enum:

```swift
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
```

This is a well-known pattern in the Swift community; several open-source implementations exist as reference. The `MCPRequest.params` and `tools/call` `arguments` fields are typed as `[String: JSONValue]?`.
