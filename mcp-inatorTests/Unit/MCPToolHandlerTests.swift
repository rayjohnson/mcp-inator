import XCTest
import MCP
@testable import mcp_inator

@MainActor
final class MCPToolHandlerTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConfigStore!
    private var handler: MCPToolHandler!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-tool-handler-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try ConfigStore(databasePath: tempDir.appendingPathComponent("test.db"))
        handler = MCPToolHandler(store: store, catalogStore: CatalogStore())
    }

    override func tearDown() async throws {
        store = nil
        handler = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func call(_ name: String, _ args: [String: Value] = [:]) async -> CallTool.Result {
        await handler.dispatch(params: CallTool.Parameters(name: name, arguments: args))
    }

    private func text(from result: CallTool.Result) -> String {
        guard let first = result.content.first,
              case .text(let t, _, _) = first else { return "" }
        return t
    }

    private func isError(_ result: CallTool.Result) -> Bool {
        result.isError == true
    }

    private func jsonArray(from result: CallTool.Result) throws -> [[String: Any]] {
        let raw = text(from: result)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]]
        )
    }

    /// Inserts an agent record pointing its config file at a temp path.
    @discardableResult
    private func seedAgent(type: AgentType) throws -> AgentRecord {
        let configPath = tempDir.appendingPathComponent("\(type.rawValue).json").path
        var agent = AgentRecord(agentType: type, configPath: configPath)
        agent.isAvailable = true
        return try store.upsertAgent(agent)
    }

    // MARK: - list_servers

    func testListServers_empty() async throws {
        let result = await call("list_servers")
        XCTAssertFalse(isError(result))
        let arr = try jsonArray(from: result)
        XCTAssertTrue(arr.isEmpty)
    }

    func testListServers_shape() async throws {
        _ = try store.insert(MCPServerConfig(displayName: "My Tool", command: "npx", args: ["--yes"]))
        let result = await call("list_servers")
        XCTAssertFalse(isError(result))
        let arr = try jsonArray(from: result)
        XCTAssertEqual(arr.count, 1)
        let entry = try XCTUnwrap(arr.first)
        XCTAssertEqual(entry["serverKey"] as? String, "my-tool")
        XCTAssertEqual(entry["displayName"] as? String, "My Tool")
        XCTAssertEqual(entry["command"] as? String, "npx")
        XCTAssertNotNil(entry["transportType"])
    }

    // MARK: - add_server

    func testAddServer_success() async throws {
        let result = await call("add_server", ["name": "Test Tool", "command": "npx"])
        XCTAssertFalse(isError(result), text(from: result))
        XCTAssertTrue(text(from: result).contains("Added"))
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.configs.first?.serverKey, "test-tool")
    }

    func testAddServer_withArgsAndEnv() async throws {
        let result = await call("add_server", [
            "name": "Playwright",
            "command": "npx",
            "args": .array(["-y", "@playwright/mcp"]),
            "env": .object(["API_KEY": "secret"])
        ])
        XCTAssertFalse(isError(result), text(from: result))
        let config = try XCTUnwrap(store.configs.first)
        XCTAssertEqual(config.args, ["-y", "@playwright/mcp"])
        XCTAssertEqual(config.envVars.first?.key, "API_KEY")
    }

    func testAddServer_duplicate() async throws {
        _ = await call("add_server", ["name": "Dupe", "command": "npx"])
        let result = await call("add_server", ["name": "Dupe", "command": "npx"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("already exists"))
        XCTAssertEqual(store.configs.count, 1)
    }

    func testAddServer_missingName() async throws {
        let result = await call("add_server", ["command": "npx"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("'name'"))
    }

    func testAddServer_missingCommand() async throws {
        let result = await call("add_server", ["name": "Tool"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("'command'"))
    }

    // MARK: - remove_server

    func testRemoveServer_success() async throws {
        _ = try store.insert(MCPServerConfig(displayName: "Removable", command: "echo"))
        XCTAssertEqual(store.configs.count, 1)
        let result = await call("remove_server", ["server_name": "removable"])
        XCTAssertFalse(isError(result), text(from: result))
        XCTAssertTrue(text(from: result).contains("Removed"))
        XCTAssertTrue(store.configs.isEmpty)
    }

    func testRemoveServer_notFound() async throws {
        let result = await call("remove_server", ["server_name": "nonexistent"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("not found"))
    }

    func testRemoveServer_builtIn() async throws {
        try store.seedSelfEntry()
        let result = await call("remove_server", ["server_name": "mcp-inator"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("built-in"))
    }

    func testRemoveServer_missingArg() async throws {
        let result = await call("remove_server")
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("'server_name'"))
    }

    // MARK: - enable_server

    func testEnableServer_appManaged() async throws {
        try store.seedSelfEntry()
        let result = await call("enable_server", ["server_name": "mcp-inator", "agent": "gemini_desktop"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("app-managed"))
    }

    func testEnableServer_unknownAgent() async throws {
        try store.seedSelfEntry()
        let result = await call("enable_server", ["server_name": "mcp-inator", "agent": "hal_9000"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("Unknown agent"))
    }

    func testEnableServer_serverNotFound() async throws {
        let result = await call("enable_server", ["server_name": "ghost", "agent": "claude_code"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("not found"))
    }

    func testEnableServer_agentNotInStore() async throws {
        _ = try store.insert(MCPServerConfig(displayName: "My Tool", command: "npx"))
        let result = await call("enable_server", ["server_name": "my-tool", "agent": "claude_code"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("not found"))
    }

    func testEnableServer_success() async throws {
        _ = try store.insert(MCPServerConfig(displayName: "My Tool", command: "npx"))
        try seedAgent(type: .claudeCode)
        handler = MCPToolHandler(store: store, catalogStore: CatalogStore(), adapterProvider: { _ in ClaudeCodeAdapter() })

        let result = await call("enable_server", ["server_name": "my-tool", "agent": "claude_code"])
        XCTAssertFalse(isError(result), text(from: result))
        XCTAssertTrue(text(from: result).contains("Enabled"))

        let configFile = tempDir.appendingPathComponent("claude_code.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configFile.path), "Adapter must write the config file")
    }

    func testEnableServer_missingArgs() async throws {
        let noServer = await call("enable_server", ["agent": "claude_code"])
        XCTAssertTrue(isError(noServer))
        XCTAssertTrue(text(from: noServer).contains("'server_name'"))

        let noAgent = await call("enable_server", ["server_name": "foo"])
        XCTAssertTrue(isError(noAgent))
        XCTAssertTrue(text(from: noAgent).contains("'agent'"))
    }

    // MARK: - disable_server

    func testDisableServer_success() async throws {
        _ = try store.insert(MCPServerConfig(displayName: "My Tool", command: "npx"))
        try seedAgent(type: .claudeCode)
        handler = MCPToolHandler(store: store, catalogStore: CatalogStore(), adapterProvider: { _ in ClaudeCodeAdapter() })

        let enableResult = await call("enable_server", ["server_name": "my-tool", "agent": "claude_code"])
        XCTAssertFalse(isError(enableResult), "Precondition: enable must succeed")

        let result = await call("disable_server", ["server_name": "my-tool", "agent": "claude_code"])
        XCTAssertFalse(isError(result), text(from: result))
        XCTAssertTrue(text(from: result).contains("Disabled"))
    }

    func testDisableServer_serverNotFound() async throws {
        let result = await call("disable_server", ["server_name": "ghost", "agent": "claude_code"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("not found"))
    }

    func testDisableServer_appManaged() async throws {
        try store.seedSelfEntry()
        let result = await call("disable_server", ["server_name": "mcp-inator", "agent": "gemini_desktop"])
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("app-managed"))
    }

    // MARK: - list_agents

    func testListAgents_empty() async throws {
        let result = await call("list_agents")
        XCTAssertFalse(isError(result))
        let arr = try jsonArray(from: result)
        XCTAssertTrue(arr.isEmpty)
    }

    func testListAgents_shape() async throws {
        try seedAgent(type: .claudeCode)
        try seedAgent(type: .geminiCLI)
        let result = await call("list_agents")
        XCTAssertFalse(isError(result))
        let arr = try jsonArray(from: result)
        XCTAssertEqual(arr.count, 2)
        for entry in arr {
            XCTAssertNotNil(entry["agentType"])
            XCTAssertNotNil(entry["displayName"])
            XCTAssertNotNil(entry["configPath"])
            XCTAssertNotNil(entry["isAvailable"])
        }
        let types = arr.compactMap { $0["agentType"] as? String }
        XCTAssertTrue(types.contains("claude_code"))
        XCTAssertTrue(types.contains("gemini_cli"))
    }

    // MARK: - Unknown tool

    func testUnknownTool() async throws {
        let result = await call("nuke_everything")
        XCTAssertTrue(isError(result))
        XCTAssertTrue(text(from: result).contains("Unknown tool"))
    }
}
