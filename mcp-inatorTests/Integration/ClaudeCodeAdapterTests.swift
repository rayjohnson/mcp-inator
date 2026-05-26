import XCTest
@testable import mcp_inator

final class ClaudeCodeAdapterTests: XCTestCase {

    private let adapter = ClaudeCodeAdapter()
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent(".claude.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Read

    func testRead_emptyFile() throws {
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertTrue(configs.isEmpty)
    }

    func testRead_validFixture() throws {
        let fixture = Bundle(for: type(of: self)).url(
            forResource: "claude_code_config", withExtension: "json"
        )!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        let github = try XCTUnwrap(configs["github-mcp"])
        XCTAssertEqual(github.command, "npx")
        XCTAssertEqual(github.args, ["@modelcontextprotocol/server-github"])
        XCTAssertEqual(github.envVars.first?.key, "GITHUB_TOKEN")
    }

    func testRead_preservesUnknownKeys() throws {
        let fixture = Bundle(for: type(of: self)).url(
            forResource: "claude_code_config", withExtension: "json"
        )!
        // Write fixture to temp, modify mcpServers, verify other keys survive
        let data = try Data(contentsOf: fixture)
        try data.write(to: configURL)

        let config = MCPServerConfig(displayName: "New", serverKey: "new-server", command: "/bin/new")
        _ = try adapter.writeConfigs(["new-server": config], to: configURL, expectedExisting: nil)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertNotNil(json["otherClaudeCodeSetting"], "Non-mcpServers keys must be preserved")
    }

    // MARK: - Write

    func testWrite_createsFileIfMissing() throws {
        let config = MCPServerConfig(displayName: "GitHub MCP", serverKey: "github-mcp", command: "npx", args: ["@github/mcp"])
        let result = try adapter.writeConfigs(["github-mcp": config], to: configURL, expectedExisting: nil)
        XCTAssertEqual(result, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertEqual(configs["github-mcp"]?.command, "npx")
    }

    func testWrite_mergesIntoExistingFile() throws {
        let first = MCPServerConfig(displayName: "First", serverKey: "first", command: "/bin/first")
        _ = try adapter.writeConfigs(["first": first], to: configURL, expectedExisting: nil)

        let second = MCPServerConfig(displayName: "Second", serverKey: "second", command: "/bin/second")
        _ = try adapter.writeConfigs(["second": second], to: configURL, expectedExisting: nil)

        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertNotNil(configs["first"], "Existing entry must be preserved")
        XCTAssertNotNil(configs["second"])
    }

    func testWrite_removesDisabledConfig() throws {
        let config = MCPServerConfig(displayName: "Temp", serverKey: "temp", command: "/bin/temp")
        _ = try adapter.writeConfigs(["temp": config], to: configURL, expectedExisting: nil)
        let result = try adapter.removeConfig(key: "temp", from: configURL, expectedValue: nil)
        XCTAssertEqual(result, .success)
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertNil(configs["temp"])
    }

    func testWrite_driftDetected() throws {
        let original = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        _ = try adapter.writeConfigs(["x": original], to: configURL, expectedExisting: nil)

        // Simulate external edit by writing different value directly
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        var servers = json["mcpServers"] as! [String: Any]
        servers["x"] = ["command": "/bin/externally-changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
            .write(to: configURL)

        // Writing with original as expectedExisting should detect drift
        let newConfig = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/updated")
        let result = try adapter.writeConfigs(["x": newConfig], to: configURL, expectedExisting: ["x": original])
        if case .driftDetected = result { } else {
            XCTFail("Expected driftDetected but got \(result)")
        }
    }

    func testWrite_driftDetected_managedKeyOnly() throws {
        // Unmanaged key added externally must NOT trigger drift
        let managed = MCPServerConfig(displayName: "M", serverKey: "m", command: "/bin/m")
        _ = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: nil)

        // Add an unmanaged key externally
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        var servers = json["mcpServers"] as! [String: Any]
        servers["external-tool"] = ["command": "/bin/external"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)

        // Writing with only "m" in expectedExisting — "external-tool" must not cause drift
        let result = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: ["m": managed])
        XCTAssertEqual(result, .success)
    }

    func testWrite_atomicOnCrash() throws {
        let readOnly = tempDir.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnly.path)
        let target = readOnly.appendingPathComponent("claude.json")
        let config = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        XCTAssertThrowsError(
            try adapter.writeConfigs(["x": config], to: target, expectedExisting: nil)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
    }

    func testWrite_removeConfig_driftDetected() throws {
        let config = MCPServerConfig(displayName: "Y", serverKey: "y", command: "/bin/y")
        _ = try adapter.writeConfigs(["y": config], to: configURL, expectedExisting: nil)

        // Externally modify the entry
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        var servers = json["mcpServers"] as! [String: Any]
        servers["y"] = ["command": "/bin/changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)

        // Remove with original as expectedValue should detect drift
        let result = try adapter.removeConfig(key: "y", from: configURL, expectedValue: config)
        if case .driftDetected = result { } else {
            XCTFail("Expected driftDetected but got \(result)")
        }
    }

    // MARK: - Validation

    func testValidateServerKey_valid() {
        XCTAssertEqual(adapter.validateServerKey("github-mcp"), .valid)
        XCTAssertEqual(adapter.validateServerKey("a"), .valid)
        XCTAssertEqual(adapter.validateServerKey("server123"), .valid)
    }

    func testValidateServerKey_reservedWorkspace() {
        if case .invalid = adapter.validateServerKey("workspace") { } else {
            XCTFail("Expected invalid for reserved key 'workspace'")
        }
    }

    func testValidateServerKey_invalid() {
        if case .invalid = adapter.validateServerKey("_bad") { } else {
            XCTFail("Expected invalid for key starting with underscore")
        }
    }
}

extension WriteResult: @retroactive Equatable {
    public static func == (lhs: WriteResult, rhs: WriteResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case (.driftDetected, .driftDetected): return true
        default: return false
        }
    }
}
