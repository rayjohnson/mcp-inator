# External Server Drift Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `AgentListView` opens for an available agent, detect server keys in the config file that mcp-inator didn't add and haven't been dismissed, and show a banner offering to import them or leave them unmanaged.

**Architecture:** A new `unmanaged_keys` DB table (Migration007) acts as a dismissal exclusion list. `ConfigStore` gains `markUnmanaged` and `scanForExternalKeys` methods; the latter re-uses the existing `categorizeImport` to classify on-disk keys, then filters out dismissed ones. `AgentListView.refreshEnabledSet` calls the scan and drives a new `externalServersBanner` subview.

**Tech Stack:** Swift, SwiftUI, GRDB (existing), XCTest

---

## File Map

| File | Action |
|---|---|
| `mcp-inator/Store/Migrations/Migration007.swift` | Create — `unmanaged_keys` table |
| `mcp-inator/Store/ConfigStore.swift` | Modify — register Migration007; add `markUnmanaged` and `scanForExternalKeys` |
| `mcp-inator/UI/AgentListView.swift` | Modify — `externalKeys` state, extend `refreshEnabledSet`, add banner + action methods |
| `mcp-inatorTests/Unit/ConfigStoreTests.swift` | Modify — add 3 new test cases |

---

## Task 1: Migration007 — `unmanaged_keys` table

**Files:**
- Create: `mcp-inator/Store/Migrations/Migration007.swift`
- Modify: `mcp-inator/Store/ConfigStore.swift` (lines 59–67, `runMigrations`)

- [ ] **Step 1: Create the migration file**

```swift
// mcp-inator/Store/Migrations/Migration007.swift
import GRDB

enum Migration007 {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("007_add_unmanaged_keys") { db in
            try db.create(table: "unmanaged_keys") { t in
                t.column("agentId", .integer).notNull().references("agents", onDelete: .cascade)
                t.column("serverKey", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.primaryKey(["agentId", "serverKey"])
            }
        }
    }
}
```

- [ ] **Step 2: Register Migration007 in `ConfigStore.runMigrations`**

In `mcp-inator/Store/ConfigStore.swift`, find `runMigrations()` (around line 59). Add one line after `Migration006.register`:

```swift
private func runMigrations() throws {
    var migrator = DatabaseMigrator()
    Migration001.register(in: &migrator)
    Migration002.register(in: &migrator)
    Migration003.register(in: &migrator)
    Migration004.register(in: &migrator)
    Migration005.register(in: &migrator)
    Migration006.register(in: &migrator)
    Migration007.register(in: &migrator)   // ← add this line
    try migrator.migrate(pool)
}
```

- [ ] **Step 3: Build to verify migration compiles**

```bash
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add mcp-inator/Store/Migrations/Migration007.swift mcp-inator/Store/ConfigStore.swift
git commit -m "Add unmanaged_keys table (Migration007)"
```

---

## Task 2: `markUnmanaged` + tests

**Files:**
- Modify: `mcp-inator/Store/ConfigStore.swift` (add method after `applyImportDecisions`)
- Modify: `mcp-inatorTests/Unit/ConfigStoreTests.swift` (add test)

- [ ] **Step 1: Write the failing test**

In `mcp-inatorTests/Unit/ConfigStoreTests.swift`, add a new `// MARK: - markUnmanaged` section after the last existing test:

```swift
// MARK: - markUnmanaged

func testMarkUnmanaged_idempotent() throws {
    let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
    let agentId = try XCTUnwrap(agent.id)

    // Calling twice with the same key must not throw (INSERT OR IGNORE)
    try store.markUnmanaged(agentId: agentId, keys: ["foo-server"])
    try store.markUnmanaged(agentId: agentId, keys: ["foo-server"])
    // Success = no error thrown
}
```

Note: `scanForExternalKeys` doesn't exist yet — the test above is intentionally self-contained. Verification that dismissal suppresses scan results is covered by `testScanForExternalKeys_returnsOnlyNewUndismissedKeys` in Task 3.

- [ ] **Step 2: Run test to confirm it fails**

```bash
make test 2>&1 | grep -E "testMarkUnmanaged|error:|FAILED"
```

Expected: compile error — `value of type 'ConfigStore' has no member 'markUnmanaged'`

- [ ] **Step 3: Implement `markUnmanaged` in ConfigStore**

In `mcp-inator/Store/ConfigStore.swift`, add this section after `applyImportDecisions` (around line 411):

```swift
// MARK: - Unmanaged Key Tracking (issue #60)

func markUnmanaged(agentId: Int64, keys: [String]) throws {
    let now = Date().timeIntervalSince1970
    try pool.write { db in
        for key in keys {
            try db.execute(
                sql: """
                     INSERT OR IGNORE INTO unmanaged_keys (agentId, serverKey, createdAt)
                     VALUES (?, ?, ?)
                     """,
                arguments: [agentId, key, now]
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
make test 2>&1 | grep -E "testMarkUnmanaged|PASSED|FAILED|error:"
```

Expected: `testMarkUnmanaged_idempotent` PASSED.

---

## Task 3: `scanForExternalKeys` + tests

**Files:**
- Modify: `mcp-inator/Store/ConfigStore.swift` (add method)
- Modify: `mcp-inatorTests/Unit/ConfigStoreTests.swift` (add two tests)

- [ ] **Step 1: Write failing tests**

In `mcp-inatorTests/Unit/ConfigStoreTests.swift`, add two more tests in the `// MARK: - markUnmanaged` section:

```swift
func testScanForExternalKeys_returnsOnlyNewUndismissedKeys() throws {
    // Library has "a-server"
    _ = try store.insert(MCPServerConfig(
        displayName: "A Server", serverKey: "a-server", command: "/bin/a"
    ))
    let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
    let agentId = try XCTUnwrap(agent.id)

    // "c-server" is already dismissed
    try store.markUnmanaged(agentId: agentId, keys: ["c-server"])

    // Config file has a-server (in library), b-server (new), c-server (dismissed)
    let adapter = StubAdapter()
    adapter.readResult = [
        "a-server": MCPServerConfig(
            displayName: "A Server", serverKey: "a-server", command: "/bin/a"
        ),
        "b-server": MCPServerConfig(
            displayName: "B Server", serverKey: "b-server", command: "/bin/b"
        ),
        "c-server": MCPServerConfig(
            displayName: "C Server", serverKey: "c-server", command: "/bin/c"
        ),
    ]

    let result = try store.scanForExternalKeys(agent: agent, adapter: adapter)
    XCTAssertEqual(result, ["b-server"])
}

func testScanForExternalKeys_allLibraryKeys_returnsEmpty() throws {
    _ = try store.insert(MCPServerConfig(
        displayName: "Known", serverKey: "known-server", command: "/bin/known"
    ))
    let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))

    let adapter = StubAdapter()
    adapter.readResult = [
        "known-server": MCPServerConfig(
            displayName: "Known", serverKey: "known-server", command: "/bin/known"
        )
    ]

    let result = try store.scanForExternalKeys(agent: agent, adapter: adapter)
    XCTAssertTrue(result.isEmpty)
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test 2>&1 | grep -E "testScan|error:|FAILED"
```

Expected: compile error — `value of type 'ConfigStore' has no member 'scanForExternalKeys'`

- [ ] **Step 3: Implement `scanForExternalKeys` in ConfigStore**

Add this method directly below `markUnmanaged`:

```swift
func scanForExternalKeys(agent: AgentRecord, adapter: any AgentAdapter) throws -> [String] {
    guard let agentId = agent.id else { return [] }
    let configPath = URL(fileURLWithPath: agent.configPath)
    let categories = try categorizeImport(from: adapter, configPath: configPath)
    let newKeys = categories.compactMap { key, category -> String? in
        if case .new = category { return key }
        return nil
    }
    let dismissed = try pool.read { db in
        try String.fetchAll(
            db,
            sql: "SELECT serverKey FROM unmanaged_keys WHERE agentId = ?",
            arguments: [agentId]
        )
    }
    let dismissedSet = Set(dismissed)
    return newKeys.filter { !dismissedSet.contains($0) }.sorted()
}
```

Note: `.sorted()` at the end ensures deterministic output, which is required for the test asserting `result == ["b-server"]`.

- [ ] **Step 4: Run tests to confirm they pass**

```bash
make test 2>&1 | grep -E "testScan|testMarkUnmanaged|PASSED|FAILED|error:"
```

Expected: all three new tests PASSED.

- [ ] **Step 5: Commit**

```bash
git add mcp-inator/Store/ConfigStore.swift mcp-inatorTests/Unit/ConfigStoreTests.swift
git commit -m "Add scanForExternalKeys and markUnmanaged to ConfigStore"
```

---

## Task 4: UI — external servers banner in `AgentListView`

**Files:**
- Modify: `mcp-inator/UI/AgentListView.swift`

- [ ] **Step 1: Add `externalKeys` state property**

In `AgentListView`, find the block of `@State` properties (around lines 11–18). Add one line:

```swift
@State private var enabledUUIDs: Set<UUID> = []
@State private var pendingWrite: PendingWrite?
@State private var pendingToggleStates: [UUID: Bool] = [:]
@State private var restartNotice: String?
@State private var writeErrorBanner: String?
@State private var showPathOverride = false
@State private var customPathInput: String = ""
@State private var cloudMCPs: [ClaudeCodeAdapter.CloudManagedMCP] = []
@State private var externalKeys: [String] = []   // ← add this line
```

- [ ] **Step 2: Extend `refreshEnabledSet` to populate `externalKeys`**

Find `refreshEnabledSet()` (around line 399). Replace the `do` block's success path so the scan runs after computing `enabledUUIDs`. The existing block looks like:

```swift
do {
    // Source of truth: the actual file on disk, matched to library configs by serverKey.
    let onDisk = try adapter.readConfigs(from: configPath)
    let diskKeys = Set(onDisk.keys)
    enabledUUIDs = Set(store.configs.compactMap { config in
        diskKeys.contains(config.serverKey) ? config.uuid : nil
    })
    // Sync DB assignment states so that enable/disable operations reconstruct
    // the config map correctly (preserving existing entries not being modified).
    for config in store.configs {
        let state: AssignmentState = diskKeys.contains(config.serverKey) ? .enabled : .disabled
        try? store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: state)
    }
} catch {
    // File unreadable — fall back to database assignment state.
    enabledUUIDs = (try? Set(store.fetchEnabledConfigs(for: agentId).map(\.uuid))) ?? []
}
```

Replace it with:

```swift
do {
    // Source of truth: the actual file on disk, matched to library configs by serverKey.
    let onDisk = try adapter.readConfigs(from: configPath)
    let diskKeys = Set(onDisk.keys)
    enabledUUIDs = Set(store.configs.compactMap { config in
        diskKeys.contains(config.serverKey) ? config.uuid : nil
    })
    // Sync DB assignment states so that enable/disable operations reconstruct
    // the config map correctly (preserving existing entries not being modified).
    for config in store.configs {
        let state: AssignmentState = diskKeys.contains(config.serverKey) ? .enabled : .disabled
        try? store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: state)
    }
    // Detect externally-added servers not yet in the library or dismissed.
    do {
        externalKeys = try store.scanForExternalKeys(agent: agent, adapter: adapter)
    } catch {
        externalKeys = []
    }
} catch {
    // File unreadable — fall back to database assignment state.
    enabledUUIDs = (try? Set(store.fetchEnabledConfigs(for: agentId).map(\.uuid))) ?? []
    externalKeys = []
}
```

- [ ] **Step 3: Restructure the `body` VStack to accommodate the banner**

Find the content section in `body` (around lines 40–54). Replace the last two branches of the if-else chain:

**Before:**
```swift
} else if store.configs.isEmpty && cloudMCPs.isEmpty {
    Spacer()
    Text("No configs in your library yet.")
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
    Spacer()
} else {
    configRows
}
```

**After:**
```swift
} else {
    if !externalKeys.isEmpty {
        externalServersBanner
        Divider()
    }
    if store.configs.isEmpty && cloudMCPs.isEmpty {
        Spacer()
        Text("No configs in your library yet.")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
        Spacer()
    } else {
        configRows
    }
}
```

- [ ] **Step 4: Add `externalServersBanner` subview**

In `AgentListView`, in the `// MARK: - Subviews` section, add after `unavailableBanner`:

```swift
private var externalServersBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.fill")
                .foregroundColor(.orange)
            Text("New server\(externalKeys.count == 1 ? "" : "s") found in config file")
                .fontWeight(.medium)
            Spacer()
        }
        Text(externalKeys.joined(separator: ", "))
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
        HStack {
            Spacer()
            Button("Leave Unmanaged") { leaveUnmanaged() }
                .buttonStyle(.bordered)
            Button("Import All") { importExternalKeys() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }
    .padding()
    .background(Color.orange.opacity(0.1))
}
```

- [ ] **Step 5: Add `importExternalKeys` action method**

In `AgentListView`, in the `// MARK: - Helpers` section, add:

```swift
private func importExternalKeys() {
    guard let agentId = agent.id else { return }
    do {
        let keysToImport = Set(externalKeys)
        let decisions: [(key: String, config: MCPServerConfig)] =
            try store.categorizeImport(from: adapter, configPath: configPath)
                .compactMap { key, category in
                    guard keysToImport.contains(key) else { return nil }
                    switch category {
                    case .new(let cfg): return (key, cfg)
                    case .exactMatch(let cfg): return (key, cfg)
                    case .conflict(let library, _): return (key, library)
                    }
                }
        try store.applyImportDecisions(decisions, agentId: agentId)
        externalKeys = []
        refreshEnabledSet()
        restartNotice = restartMessageText
    } catch {
        writeErrorBanner = describeError(error, configPath: configPath)
    }
}

private func leaveUnmanaged() {
    guard let agentId = agent.id else { return }
    do {
        try store.markUnmanaged(agentId: agentId, keys: externalKeys)
        externalKeys = []
    } catch {
        writeErrorBanner = describeError(error, configPath: configPath)
    }
}
```

- [ ] **Step 6: Build and verify it compiles**

```bash
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run tests and lint**

```bash
make test 2>&1 | tail -10
make lint 2>&1 | grep -c "warning\|error" || echo "0 issues"
```

Expected: all tests pass, zero SwiftLint warnings.

- [ ] **Step 8: Commit**

```bash
git add mcp-inator/UI/AgentListView.swift
git commit -m "Surface externally-added servers for import in AgentListView (#60)"
```

---

## Final Checks Before PR

- [ ] Run `make cover` and verify coverage threshold passes
- [ ] Bump patch version in `VERSION`
- [ ] Add entry to `RELEASE_NOTES.md`
- [ ] Run `make lint` one final time — zero warnings required
