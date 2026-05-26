import XCTest
@testable import mcp_inator

@MainActor
final class AgentVisibilityTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConfigStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-visibility-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try ConfigStore(databasePath: tempDir.appendingPathComponent("test.db"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testNewAgent_isVisibleByDefault() throws {
        var agent = AgentRecord(agentType: .claudeCode)
        agent.isAvailable = true
        let upserted = try store.upsertAgent(agent)
        XCTAssertTrue(upserted.isVisible)
    }

    func testVisibleAgents_excludesHiddenAgents() throws {
        var a1 = AgentRecord(agentType: .claudeCode)
        a1.isAvailable = true
        let inserted1 = try store.upsertAgent(a1)

        var a2 = AgentRecord(agentType: .claudeDesktop)
        a2.isAvailable = true
        _ = try store.upsertAgent(a2)

        guard let id1 = inserted1.id else { XCTFail("No id"); return }
        try store.setAgentVisibility(agentId: id1, visible: false)

        XCTAssertEqual(store.agents.count, 2)
        XCTAssertEqual(store.visibleAgents.count, 1)
        XCTAssertEqual(store.visibleAgents.first?.agentType, .claudeDesktop)
    }

    func testSetAgentVisibility_togglesCorrectly() throws {
        var agent = AgentRecord(agentType: .geminiDesktop)
        agent.isAvailable = true
        let inserted = try store.upsertAgent(agent)
        guard let agentId = inserted.id else { XCTFail("No id"); return }

        try store.setAgentVisibility(agentId: agentId, visible: false)
        XCTAssertEqual(store.visibleAgents.count, 0)

        try store.setAgentVisibility(agentId: agentId, visible: true)
        XCTAssertEqual(store.visibleAgents.count, 1)
    }

    func testFetchStatusMatrix_excludesHiddenAgents() throws {
        var agent = AgentRecord(agentType: .claudeCode)
        agent.isAvailable = true
        let inserted = try store.upsertAgent(agent)
        guard let agentId = inserted.id else { XCTFail("No id"); return }

        let config = MCPServerConfig(displayName: "TestServer", command: "/bin/test")
        _ = try store.insert(config)

        var rows = try store.fetchStatusMatrix()
        XCTAssertEqual(rows.first?.agentStates.count, 1)

        try store.setAgentVisibility(agentId: agentId, visible: false)
        rows = try store.fetchStatusMatrix()
        XCTAssertEqual(rows.first?.agentStates.count, 0)
    }
}
