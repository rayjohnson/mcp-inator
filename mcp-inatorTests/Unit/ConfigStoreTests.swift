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

    // MARK: - categorizeImport

    func testCategorizeImport_newServer_classifiedAsNew() throws {
        let adapter = StubAdapter()
        adapter.readResult = ["my-tool": MCPServerConfig(displayName: "My Tool", command: "/bin/tool")]
        let results = try store.categorizeImport(from: adapter, configPath: adapter.configPathResult)
        XCTAssertEqual(results.count, 1)
        if case .new = results[0].category { } else {
            XCTFail("Expected .new, got \(results[0].category)")
        }
    }

    func testCategorizeImport_exactMatch_classifiedAsExactMatch() throws {
        let config = MCPServerConfig(displayName: "My Tool", command: "/bin/tool")
        _ = try store.insert(config)

        let adapter = StubAdapter()
        adapter.readResult = ["my-tool": config]
        let results = try store.categorizeImport(from: adapter, configPath: adapter.configPathResult)
        XCTAssertEqual(results.count, 1)
        if case .exactMatch = results[0].category { } else {
            XCTFail("Expected .exactMatch, got \(results[0].category)")
        }
    }

    func testCategorizeImport_conflict_classifiedAsConflict() throws {
        _ = try store.insert(MCPServerConfig(displayName: "My Tool", command: "/bin/old"))

        let adapter = StubAdapter()
        adapter.readResult = ["my-tool": MCPServerConfig(displayName: "My Tool", command: "/bin/new")]
        let results = try store.categorizeImport(from: adapter, configPath: adapter.configPathResult)
        XCTAssertEqual(results.count, 1)
        if case .conflict = results[0].category { } else {
            XCTFail("Expected .conflict, got \(results[0].category)")
        }
    }

    func testCategorizeImport_skipsBuiltInKey() throws {
        let adapter = StubAdapter()
        adapter.readResult = ["mcp-inator": MCPServerConfig(displayName: "Built-in", command: "/bin/self")]
        let results = try store.categorizeImport(from: adapter, configPath: adapter.configPathResult)
        XCTAssertTrue(results.isEmpty, "Built-in 'mcp-inator' key must be skipped")
    }

    func testCategorizeImport_emptyAdapter_returnsEmpty() throws {
        let adapter = StubAdapter()
        adapter.readResult = [:]
        let results = try store.categorizeImport(from: adapter, configPath: adapter.configPathResult)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - applyImportDecisions — agentId nil (new import flow)

    func testApplyImportDecisions_nilAgentId_insertsConfig() throws {
        let config = MCPServerConfig(displayName: "New Tool", command: "/bin/tool")
        try store.applyImportDecisions([(key: "new-tool", config: config)], agentId: nil)
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.configs.first?.serverKey, "new-tool")
    }

    func testApplyImportDecisions_nilAgentId_noAssignmentCreated() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let config = MCPServerConfig(displayName: "New Tool", command: "/bin/tool")
        try store.applyImportDecisions([(key: "new-tool", config: config)], agentId: nil)

        let inserted = try XCTUnwrap(store.configs.first)
        let assignment = try store.fetchAssignment(configUUID: inserted.uuid, agentId: agentId)
        XCTAssertNil(assignment, "No assignment must be created when agentId is nil")
    }

    func testApplyImportDecisions_nilAgentId_updatesExistingConfig() throws {
        let original = try store.insert(MCPServerConfig(displayName: "My Tool", command: "/bin/old"))
        // The updated config must carry the same serverKey so applyImportDecisions finds the existing record.
        let updated = MCPServerConfig(displayName: "My Tool", serverKey: original.serverKey,
                                      command: "/bin/new")
        try store.applyImportDecisions([(key: original.serverKey, config: updated)], agentId: nil)

        let fetched = try XCTUnwrap(try store.fetch(uuid: original.uuid))
        XCTAssertEqual(fetched.command, "/bin/new")
        XCTAssertEqual(store.configs.count, 1, "Update must not create a second record")
    }

    // MARK: - applyImportDecisions — agentId set (existing discovery flow, regression)

    func testApplyImportDecisions_withAgentId_insertsConfig() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let config = MCPServerConfig(displayName: "Tool", command: "/bin/tool")
        try store.applyImportDecisions([(key: "tool", config: config)], agentId: agentId)
        XCTAssertEqual(store.configs.count, 1)
    }

    func testApplyImportDecisions_withAgentId_createsAssignment() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let config = MCPServerConfig(displayName: "Tool", command: "/bin/tool")
        try store.applyImportDecisions([(key: "tool", config: config)], agentId: agentId)

        let inserted = try XCTUnwrap(store.configs.first)
        let assignment = try store.fetchAssignment(configUUID: inserted.uuid, agentId: agentId)
        XCTAssertNotNil(assignment, "Assignment must be created when agentId is provided")
        XCTAssertEqual(assignment?.state, .enabled)
    }

    // MARK: - updateAgentAvailability

    func testUpdateAgentAvailability_reflectedInPublishedAgents() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)

        try store.updateAgentAvailability(agentId: agentId, isAvailable: true)
        XCTAssertTrue(store.agents.first(where: { $0.id == agentId })?.isAvailable ?? false)

        try store.updateAgentAvailability(agentId: agentId, isAvailable: false)
        XCTAssertFalse(store.agents.first(where: { $0.id == agentId })?.isAvailable ?? true)
    }

    // MARK: - updateAgentConfigPath

    func testUpdateAgentConfigPath_reflectedInPublishedAgents() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let newPath = "/tmp/custom-claude.json"

        try store.updateAgentConfigPath(agentId: agentId, path: newPath)
        XCTAssertEqual(store.agents.first(where: { $0.id == agentId })?.configPath, newPath)
    }

    // MARK: - findEnabledAgents

    func testFindEnabledAgents_returnsAgentsWithEnabledAssignment() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let config = try store.insert(MCPServerConfig(displayName: "Tool", command: "npx"))

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .enabled)

        let found = try store.findEnabledAgents(for: config.uuid)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.agentType, .claudeCode)
    }

    func testFindEnabledAgents_emptyWhenNoAssignment() throws {
        let config = try store.insert(MCPServerConfig(displayName: "Tool", command: "npx"))
        let found = try store.findEnabledAgents(for: config.uuid)
        XCTAssertTrue(found.isEmpty)
    }

    func testFindEnabledAgents_ignoresDisabledAssignment() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let config = try store.insert(MCPServerConfig(displayName: "Tool", command: "npx"))

        try store.setAssignmentState(configUUID: config.uuid, agentId: agentId, state: .disabled)

        let found = try store.findEnabledAgents(for: config.uuid)
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: - bulkEnableConfigs

    func testBulkEnableConfigs_allSucceed() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let configPath = tempDir.appendingPathComponent("claude_code.json")

        let c1 = try store.insert(MCPServerConfig(displayName: "Tool A", command: "npx"))
        let c2 = try store.insert(MCPServerConfig(displayName: "Tool B", command: "uvx"))

        let result = try store.bulkEnableConfigs(
            uuids: [c1.uuid, c2.uuid],
            agentId: agentId,
            adapter: MockAdapter(),
            configPath: configPath
        )
        XCTAssertEqual(result.succeeded.count, 2)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(result.driftDetected.isEmpty)
    }

    func testBulkEnableConfigs_unknownUUIDGoesToFailed() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)
        let configPath = tempDir.appendingPathComponent("claude_code.json")

        let result = try store.bulkEnableConfigs(
            uuids: [UUID()],
            agentId: agentId,
            adapter: MockAdapter(),
            configPath: configPath
        )
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failed.count, 1)
    }

    // MARK: - markUnmanaged

    func testMarkUnmanaged_idempotent() throws {
        let agent = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let agentId = try XCTUnwrap(agent.id)

        // Calling twice with the same key must not throw (INSERT OR IGNORE)
        try store.markUnmanaged(agentId: agentId, keys: ["foo-server"])
        try store.markUnmanaged(agentId: agentId, keys: ["foo-server"])
        // Success = no error thrown
    }

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

}
