import XCTest
@testable import mcp_inator

final class CodexCLIAdapterTests: XCTestCase {

    private let adapter = CodexCLIAdapter()
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRead_emptyFile() throws {
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    func testRead_validFixture() throws {
        let fixture = Bundle(for: type(of: self)).url(forResource: "codex_config", withExtension: "toml")!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        let github = try XCTUnwrap(configs["github-mcp"])
        XCTAssertEqual(github.command, "npx")
        XCTAssertEqual(github.args, ["@modelcontextprotocol/server-github"])
        XCTAssertEqual(github.envVars.first?.key, "GITHUB_TOKEN")
    }

    func testRead_preservesUnknownKeys() throws {
        let fixture = Bundle(for: type(of: self)).url(forResource: "codex_config", withExtension: "toml")!
        try (try String(contentsOf: fixture)).write(to: configURL, atomically: true, encoding: .utf8)
        let config = MCPServerConfig(displayName: "New", serverKey: "new-server", command: "/bin/new")
        _ = try adapter.writeConfigs(["new-server": config], to: configURL, expectedExisting: nil)
        let raw = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("other_codex_setting"), "Non-mcp_servers TOML keys must be preserved")
    }

    func testWrite_createsFileIfMissing() throws {
        let config = MCPServerConfig(displayName: "Test", serverKey: "test", command: "/bin/test")
        XCTAssertEqual(try adapter.writeConfigs(["test": config], to: configURL, expectedExisting: nil), .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testWrite_mergesIntoExistingFile() throws {
        let c1 = MCPServerConfig(displayName: "One", serverKey: "one", command: "/bin/one")
        _ = try adapter.writeConfigs(["one": c1], to: configURL, expectedExisting: nil)
        let c2 = MCPServerConfig(displayName: "Two", serverKey: "two", command: "/bin/two")
        _ = try adapter.writeConfigs(["two": c2], to: configURL, expectedExisting: nil)
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertNotNil(configs["one"])
        XCTAssertNotNil(configs["two"])
    }

    func testWrite_removesDisabledConfig() throws {
        let config = MCPServerConfig(displayName: "R", serverKey: "r", command: "/bin/r")
        _ = try adapter.writeConfigs(["r": config], to: configURL, expectedExisting: nil)
        let result = try adapter.removeConfig(key: "r", from: configURL, expectedValue: nil)
        XCTAssertEqual(result, .success)
        XCTAssertNil(try adapter.readConfigs(from: configURL)["r"])
    }

    func testWrite_driftDetected() throws {
        let original = MCPServerConfig(displayName: "D", serverKey: "d", command: "/bin/d")
        _ = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: nil)
        // Modify the TOML directly
        let tomlContent = """
        [mcp_servers.d]
        command = "/bin/changed"
        """
        try tomlContent.write(to: configURL, atomically: true, encoding: .utf8)
        let result = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: ["d": original])
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    func testWrite_driftDetected_managedKeyOnly() throws {
        let m = MCPServerConfig(displayName: "M", serverKey: "m", command: "/bin/m")
        _ = try adapter.writeConfigs(["m": m], to: configURL, expectedExisting: nil)
        let extraTOML = try String(contentsOf: configURL) + "\n[mcp_servers.unmanaged]\ncommand = \"/bin/ext\"\n"
        try extraTOML.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try adapter.writeConfigs(["m": m], to: configURL, expectedExisting: ["m": m]), .success)
    }

    func testWrite_atomicOnCrash() throws {
        let ro = tempDir.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: ro.path)
        let target = ro.appendingPathComponent("config.toml")
        let config = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        XCTAssertThrowsError(try adapter.writeConfigs(["x": config], to: target, expectedExisting: nil))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path)
    }

    func testWrite_removeConfig_driftDetected() throws {
        let config = MCPServerConfig(displayName: "Z", serverKey: "z", command: "/bin/z")
        _ = try adapter.writeConfigs(["z": config], to: configURL, expectedExisting: nil)
        let changedTOML = """
        [mcp_servers.z]
        command = "/bin/changed"
        """
        try changedTOML.write(to: configURL, atomically: true, encoding: .utf8)
        let result = try adapter.removeConfig(key: "z", from: configURL, expectedValue: config)
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    func testValidateServerKey_valid() {
        XCTAssertEqual(adapter.validateServerKey("github-mcp"), .valid)
        XCTAssertEqual(adapter.validateServerKey("my_server"), .valid)  // underscores OK for Codex
    }

    func testValidateServerKey_invalid() {
        if case .invalid = adapter.validateServerKey("-leading") { } else { XCTFail("Expected invalid") }
    }
}
