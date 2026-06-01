import XCTest
@testable import mcp_inator

@MainActor
final class ConfigStoreDiscoveryTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConfigStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-discovery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try ConfigStore(databasePath: tempDir.appendingPathComponent("test.db"))
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - discoverAgents

    func testDiscoverAgents_emptyAdapters_returnsEmpty() throws {
        let results = try store.discoverAgents(adapters: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testDiscoverAgents_installedAdapter_freshDB_isNew() throws {
        let adapter = StubAdapter(agentType: .claudeCode)
        let results = try store.discoverAgents(adapters: [adapter])
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isNew)
        XCTAssertEqual(results[0].agent.agentType, .claudeCode)
    }

    func testDiscoverAgents_installedAdapter_existingRecord_isNotNew() throws {
        _ = try store.upsertAgent(AgentRecord(agentType: .claudeCode))
        let adapter = StubAdapter(agentType: .claudeCode)
        let results = try store.discoverAgents(adapters: [adapter])
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isNew)
    }

    func testDiscoverAgents_notInstalledAdapter_excluded() throws {
        let adapter = StubAdapter(agentType: .claudeCode)
        adapter.installedResult = false
        let results = try store.discoverAgents(adapters: [adapter])
        XCTAssertTrue(results.isEmpty)
    }

    func testDiscoverAgents_mixedInstalled_onlyInstalledIncluded() throws {
        let installed = StubAdapter(agentType: .claudeCode)
        let notInstalled = StubAdapter(agentType: .claudeDesktop)
        notInstalled.installedResult = false
        let alsoInstalled = StubAdapter(agentType: .geminiCLI)

        let results = try store.discoverAgents(adapters: [installed, notInstalled, alsoInstalled])
        XCTAssertEqual(results.count, 2)
        let types = results.map { $0.agent.agentType }
        XCTAssertTrue(types.contains(.claudeCode))
        XCTAssertTrue(types.contains(.geminiCLI))
        XCTAssertFalse(types.contains(.claudeDesktop))
    }

    func testDiscoverAgents_installedAdapter_setsAvailableFlag() throws {
        let adapter = StubAdapter(agentType: .claudeCode)
        _ = try store.discoverAgents(adapters: [adapter])
        XCTAssertTrue(store.agents.first?.isAvailable ?? false)
    }

    func testDiscoverAgents_twoFreshAdapters_bothAreNew() throws {
        let a1 = StubAdapter(agentType: .claudeCode)
        let a2 = StubAdapter(agentType: .claudeDesktop)
        let results = try store.discoverAgents(adapters: [a1, a2])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.isNew })
    }

    // MARK: - refreshAvailability

    func testRefreshAvailability_installedAdapter_setsAvailable() throws {
        var agent = AgentRecord(agentType: .claudeCode)
        agent.isAvailable = false
        _ = try store.upsertAgent(agent)

        let adapter = StubAdapter(agentType: .claudeCode)
        adapter.installedResult = true
        try store.refreshAvailability(adapters: [adapter])

        XCTAssertTrue(store.agents.first?.isAvailable ?? false)
    }

    func testRefreshAvailability_notInstalledAdapter_clearsAvailable() throws {
        var agent = AgentRecord(agentType: .claudeCode)
        agent.isAvailable = true
        _ = try store.upsertAgent(agent)

        let adapter = StubAdapter(agentType: .claudeCode)
        adapter.installedResult = false
        try store.refreshAvailability(adapters: [adapter])

        XCTAssertFalse(store.agents.first?.isAvailable ?? true)
    }

    func testRefreshAvailability_noMatchingAdapter_agentUnchanged() throws {
        var agent = AgentRecord(agentType: .claudeCode)
        agent.isAvailable = true
        _ = try store.upsertAgent(agent)

        let unrelatedAdapter = StubAdapter(agentType: .cursor)
        try store.refreshAvailability(adapters: [unrelatedAdapter])

        XCTAssertTrue(
            store.agents.first?.isAvailable ?? false,
            "Agent with no matching adapter must retain its current state"
        )
    }
}
