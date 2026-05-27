import XCTest
@testable import mcp_inator

// MARK: - MockAdapter

/// Records calls to writeConfigs without touching the filesystem.
/// Used to verify what ConfigStore passes to the adapter layer.
private final class MockAdapter: AgentAdapter, @unchecked Sendable {
    let agentType: AgentType = .claudeCode
    let displayName = "Mock"

    var capturedConfigs: [String: MCPServerConfig]?
    var capturedExpectedExisting: [String: MCPServerConfig]?
    var capturedExpectedExistingWasNil = false
    var writeResult: WriteResult = .success

    func defaultConfigPath() -> URL { URL(fileURLWithPath: "/dev/null") }
    func isInstalled() -> Bool { true }
    func readConfigs(from path: URL) throws -> [String: MCPServerConfig] { [:] }
    func writeConfigs(
        _ configs: [String: MCPServerConfig],
        to path: URL,
        expectedExisting: [String: MCPServerConfig]?
    ) throws -> WriteResult {
        capturedConfigs = configs
        capturedExpectedExisting = expectedExisting
        capturedExpectedExistingWasNil = expectedExisting == nil
        return writeResult
    }
    func removeConfig(key: String, from path: URL, expectedValue: MCPServerConfig?) throws -> WriteResult { .success }
    func validateServerKey(_ key: String) -> KeyValidationResult { .valid }
}

@MainActor
final class ConfigStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConfigStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try ConfigStore(databasePath: tempDir.appendingPathComponent("test.db"))
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - MCPServerConfig CRUD

    func testInsert_roundTrip() throws {
        let config = MCPServerConfig(displayName: "GitHub MCP", command: "npx",
                                     args: ["@github/mcp"],
                                     envVars: [EnvVar(key: "TOKEN", value: "abc")])
        let inserted = try store.insert(config)
        XCTAssertNotNil(inserted.id)
        XCTAssertEqual(inserted.serverKey, "github-mcp")
        XCTAssertEqual(store.configs.count, 1)
    }

    func testFetchByUUID() throws {
        let config = MCPServerConfig(displayName: "Obsidian", command: "/usr/bin/obs")
        let inserted = try store.insert(config)
        let fetched = try store.fetch(uuid: inserted.uuid)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.serverKey, "obsidian")
    }

    func testFetchByUUID_unknownUUID_returnsNil() throws {
        XCTAssertNil(try store.fetch(uuid: UUID()))
    }

    func testUpdate_changesFields() throws {
        var config = try store.insert(MCPServerConfig(displayName: "Old Name", command: "/bin/old"))
        config.displayName = "New Name"
        config.command = "/bin/new"
        try store.update(config)
        let fetched = try XCTUnwrap(try store.fetch(uuid: config.uuid))
        XCTAssertEqual(fetched.displayName, "New Name")
        XCTAssertEqual(fetched.command, "/bin/new")
    }

    func testDelete_removesConfig() throws {
        let config = try store.insert(MCPServerConfig(displayName: "Temp", command: "/bin/tmp"))
        XCTAssertEqual(store.configs.count, 1)
        try store.delete(config)
        XCTAssertTrue(store.configs.isEmpty)
        XCTAssertNil(try store.fetch(uuid: config.uuid))
    }

    // MARK: - Cascade Delete

    func testDelete_cascadesToAssignments() throws {
        let config = try store.insert(MCPServerConfig(displayName: "C", command: "/bin/c"))
        var agent = AgentRecord(agentType: .claudeCode)
        agent = try store.upsertAgent(agent)
        let agentId = try XCTUnwrap(agent.id)

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .enabled)
        let before = try store.fetchAssignment(configUUID: config.uuid, agentId: agentId)
        XCTAssertNotNil(before)

        try store.delete(config)
        let after = try store.fetchAssignment(configUUID: config.uuid, agentId: agentId)
        XCTAssertNil(after, "Assignment must be deleted when config is deleted")
    }

    // MARK: - AgentRecord

    func testUpsertAgent_insertsFirst() throws {
        let agent = AgentRecord(agentType: .geminiCLI)
        let upserted = try store.upsertAgent(agent)
        XCTAssertNotNil(upserted.id)
        XCTAssertEqual(store.agents.count, 1)
    }

    func testUpsertAgent_updatesExisting() throws {
        var agent = AgentRecord(agentType: .claudeDesktop)
        agent = try store.upsertAgent(agent)
        agent.isAvailable = true
        let updated = try store.upsertAgent(agent)
        XCTAssertEqual(store.agents.count, 1, "Upsert must not insert a duplicate")
        XCTAssertTrue(updated.isAvailable)
    }

    // MARK: - Assignments

    func testSetAssignment_createsNew() throws {
        let config = try store.insert(MCPServerConfig(displayName: "X", command: "/bin/x"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .codexCLI))
        let agentId = try XCTUnwrap(agent.id)

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .enabled)
        let assignment = try XCTUnwrap(store.fetchAssignment(configUUID: config.uuid, agentId: agentId))
        XCTAssertEqual(assignment.state, .enabled)
        XCTAssertNil(assignment.lastWrittenSnapshot)
    }

    func testSetAssignment_updatesExisting() throws {
        let config = try store.insert(MCPServerConfig(displayName: "Y", command: "/bin/y"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .enabled)
        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .disabled)

        let assignment = try XCTUnwrap(store.fetchAssignment(configUUID: config.uuid, agentId: agentId))
        XCTAssertEqual(assignment.state, .disabled)
    }

    func testSetAssignment_storesSnapshot() throws {
        let config = try store.insert(MCPServerConfig(displayName: "S", command: "/bin/s"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .enabled, snapshot: config)
        let assignment = try XCTUnwrap(store.fetchAssignment(configUUID: config.uuid, agentId: agentId))
        XCTAssertNotNil(assignment.lastWrittenSnapshot)
        XCTAssertEqual(assignment.lastWrittenSnapshot?.command, "/bin/s")
    }

    func testFetchEnabledConfigs_returnsOnlyEnabled() throws {
        let c1 = try store.insert(MCPServerConfig(displayName: "Enabled", command: "/bin/e"))
        let c2 = try store.insert(MCPServerConfig(displayName: "Disabled", command: "/bin/d"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)

        try store.setAssignmentState(configUUID: c1.uuid, agentId: agentId, state: .enabled)
        try store.setAssignmentState(configUUID: c2.uuid, agentId: agentId, state: .disabled)

        let enabled = try store.fetchEnabledConfigs(for: agentId)
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.serverKey, "enabled")
    }

    func testFetchEnabledConfigs_emptyWhenNoneEnabled() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .geminiCLI))
        let agentId = try XCTUnwrap(agent.id)
        XCTAssertTrue(try store.fetchEnabledConfigs(for: agentId).isEmpty)
    }

    // MARK: - Multiple configs / agents

    func testInsertMultipleConfigs() throws {
        _ = try store.insert(MCPServerConfig(displayName: "A", command: "/bin/a"))
        _ = try store.insert(MCPServerConfig(displayName: "B", command: "/bin/b"))
        _ = try store.insert(MCPServerConfig(displayName: "C", command: "/bin/c"))
        XCTAssertEqual(store.configs.count, 3)
    }

    func testSeedSelfEntry_idempotent() throws {
        try store.seedSelfEntry()
        try store.seedSelfEntry()
        let count = store.configs.filter { $0.serverKey == "mcp-inator" }.count
        XCTAssertEqual(count, 1, "seedSelfEntry must not insert a duplicate")
    }

    func testPublishedConfigs_updatesAfterInsertAndDelete() throws {
        XCTAssertTrue(store.configs.isEmpty)
        let config = try store.insert(MCPServerConfig(displayName: "Live", command: "/bin/live"))
        XCTAssertEqual(store.configs.count, 1)
        try store.delete(config)
        XCTAssertTrue(store.configs.isEmpty)
    }

    // MARK: - enableConfig

    // Regression: when enabling server B while the built-in (mcp-inator) is already
    // enabled, the configMap passed to the adapter must use the real executable path
    // for mcp-inator — not the "" the DB stores. Before the fix, enabledConfigs were
    // copied to configMap with raw DB values, so every non-builtin enable wrote
    // command="" for mcp-inator to disk, causing the stored snapshot (exec path) to
    // drift from what was on disk.
    func testEnableConfig_builtInCommandNotStomped() throws {
        try store.seedSelfEntry()
        let builtIn = try XCTUnwrap(store.configs.first { $0.isBuiltIn })
        let regular = try store.insert(MCPServerConfig(displayName: "Regular", command: "/bin/regular"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let configPath = tempDir.appendingPathComponent("test.json")

        // Enable the built-in first so it appears in enabledConfigs on the next call.
        _ = try store.enableConfig(uuid: builtIn.uuid, agentId: agentId,
                                    adapter: MockAdapter(), configPath: configPath)

        // Now enable the regular server. The configMap must include mcp-inator with
        // a non-empty command, not the "" stored in the DB.
        let adapter = MockAdapter()
        _ = try store.enableConfig(uuid: regular.uuid, agentId: agentId,
                                    adapter: adapter, configPath: configPath)

        let writtenBuiltIn = try XCTUnwrap(adapter.capturedConfigs?[builtIn.serverKey])
        XCTAssertFalse(writtenBuiltIn.command.isEmpty,
                       "Built-in server command must be resolved to executable path, not left empty in configMap")
    }

    func testEnableConfig_driftResult_propagates_andSkipsSnapshot() throws {
        let config = try store.insert(MCPServerConfig(displayName: "X", command: "/bin/x"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let configPath = tempDir.appendingPathComponent("test.json")

        let driftAdapter = MockAdapter()
        driftAdapter.writeResult = .driftDetected(onDisk: [:], expected: [:])

        let result = try store.enableConfig(uuid: config.uuid, agentId: agentId,
                                             adapter: driftAdapter, configPath: configPath)
        if case .driftDetected = result { } else {
            XCTFail("Expected driftDetected to be propagated from adapter")
        }
        XCTAssertNil(try store.fetchAssignment(configUUID: config.uuid, agentId: agentId),
                     "Assignment must not be created when drift is detected")
    }

    func testEnableConfig_force_passesNilExpectedExisting() throws {
        // After the first enable creates a snapshot, a normal second enable includes
        // expectedExisting. force=true must bypass that and pass nil to the adapter.
        let c1 = try store.insert(MCPServerConfig(displayName: "A", command: "/bin/a"))
        let c2 = try store.insert(MCPServerConfig(displayName: "B", command: "/bin/b"))
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let configPath = tempDir.appendingPathComponent("test.json")

        _ = try store.enableConfig(uuid: c1.uuid, agentId: agentId,
                                    adapter: MockAdapter(), configPath: configPath)

        let normalAdapter = MockAdapter()
        _ = try store.enableConfig(uuid: c2.uuid, agentId: agentId,
                                    adapter: normalAdapter, configPath: configPath)
        XCTAssertFalse(normalAdapter.capturedExpectedExistingWasNil,
                       "Normal enable must pass expectedExisting to adapter when snapshots exist")

        let forceAdapter = MockAdapter()
        _ = try store.enableConfig(uuid: c2.uuid, agentId: agentId,
                                    adapter: forceAdapter, configPath: configPath, force: true)
        XCTAssertTrue(forceAdapter.capturedExpectedExistingWasNil,
                      "force=true must pass nil expectedExisting to adapter")
    }
}
