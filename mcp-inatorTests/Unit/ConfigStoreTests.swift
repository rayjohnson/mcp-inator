import XCTest
@testable import mcp_inator

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

    func testPublishedConfigs_updatesAfterInsertAndDelete() throws {
        XCTAssertTrue(store.configs.isEmpty)
        let config = try store.insert(MCPServerConfig(displayName: "Live", command: "/bin/live"))
        XCTAssertEqual(store.configs.count, 1)
        try store.delete(config)
        XCTAssertTrue(store.configs.isEmpty)
    }
}
