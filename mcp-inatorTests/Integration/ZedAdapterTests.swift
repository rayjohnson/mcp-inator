import XCTest
@testable import mcp_inator

final class ZedAdapterTests: XCTestCase {

    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-zed-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var adapter: ZedAdapter {
        ZedAdapter(homeDirectory: tempDir, appBundlePath: tempDir.appendingPathComponent("Zed.app").path)
    }

    // MARK: - Read

    func testRead_emptyFile() throws {
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertTrue(configs.isEmpty)
    }

    func testRead_validFixture() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "zed_settings", withExtension: "json")!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        let github = try XCTUnwrap(configs["github-mcp"])
        XCTAssertEqual(github.command, "npx")
        XCTAssertEqual(github.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(github.envVars.first?.key, "GITHUB_TOKEN")
    }

    func testRead_malformedJSON() throws {
        try "{invalid".write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try adapter.readConfigs(from: configURL))
    }

    func testRead_preservesUnknownKeys() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "zed_settings", withExtension: "json")!
        try (try Data(contentsOf: fixture)).write(to: configURL)

        let config = MCPServerConfig(displayName: "New", serverKey: "new-server", command: "/bin/new")
        _ = try adapter.writeConfigs(["new-server": config], to: configURL, expectedExisting: nil)

        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertNotNil(json["otherZedSetting"], "Non-context_servers keys must be preserved")
    }

    // MARK: - Write

    func testWrite_createsFileIfMissing() throws {
        let config = MCPServerConfig(displayName: "GitHub MCP", serverKey: "github-mcp", command: "npx", args: ["-y", "@github/mcp"])
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

    func testWrite_driftDetected() throws {
        let original = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        _ = try adapter.writeConfigs(["x": original], to: configURL, expectedExisting: nil)

        // Externally modify the entry
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["context_servers"] as! [String: Any]
        servers["x"] = ["command": ["path": "/bin/externally-changed", "args": []]]
        json["context_servers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)

        let newConfig = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/updated")
        let result = try adapter.writeConfigs(["x": newConfig], to: configURL, expectedExisting: ["x": original])
        if case .driftDetected = result { } else {
            XCTFail("Expected driftDetected but got \(result)")
        }
    }

    func testWrite_driftDetected_managedKeyOnly() throws {
        let managed = MCPServerConfig(displayName: "M", serverKey: "m", command: "/bin/m")
        _ = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: nil)

        // Add an unmanaged external entry — must NOT trigger drift
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["context_servers"] as! [String: Any]
        servers["external-tool"] = ["command": ["path": "/bin/external", "args": []]]
        json["context_servers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)

        let result = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: ["m": managed])
        XCTAssertEqual(result, .success)
    }

    // MARK: - Remove

    func testRemoveConfig() throws {
        let config = MCPServerConfig(displayName: "Temp", serverKey: "temp", command: "/bin/temp")
        _ = try adapter.writeConfigs(["temp": config], to: configURL, expectedExisting: nil)
        let result = try adapter.removeConfig(key: "temp", from: configURL, expectedValue: nil)
        XCTAssertEqual(result, .success)
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertNil(configs["temp"])
    }

    func testRemoveConfig_driftDetected() throws {
        let config = MCPServerConfig(displayName: "Y", serverKey: "y", command: "/bin/y")
        _ = try adapter.writeConfigs(["y": config], to: configURL, expectedExisting: nil)

        // Externally modify the entry
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["context_servers"] as! [String: Any]
        servers["y"] = ["command": ["path": "/bin/changed", "args": []]]
        json["context_servers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)

        let result = try adapter.removeConfig(key: "y", from: configURL, expectedValue: config)
        if case .driftDetected = result { } else {
            XCTFail("Expected driftDetected but got \(result)")
        }
    }

    // MARK: - isInstalled

    func testIsInstalled_emptyTempDir_returnsFalse() throws {
        XCTAssertFalse(adapter.isInstalled())
    }

    func testIsInstalled_settingsFileExists_returnsTrue() throws {
        let zedDir = tempDir.appendingPathComponent(".config/zed")
        try FileManager.default.createDirectory(at: zedDir, withIntermediateDirectories: true)
        try "{}".write(to: zedDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(adapter.isInstalled())
    }

    func testIsInstalled_zedDirExists_returnsTrue() throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".config/zed"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(adapter.isInstalled())
    }

    func testIsInstalled_unrelatedFilesOnly_returnsFalse() throws {
        try "{}".write(to: tempDir.appendingPathComponent("other.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(adapter.isInstalled())
    }

    func testIsInstalled_appBundleExists_returnsTrue() throws {
        let fakeBundlePath = tempDir.appendingPathComponent("Zed.app").path
        try FileManager.default.createDirectory(atPath: fakeBundlePath, withIntermediateDirectories: true)
        let zed = ZedAdapter(homeDirectory: tempDir, appBundlePath: fakeBundlePath)
        XCTAssertTrue(zed.isInstalled())
    }

    func testDefaultConfigPath_usesInjectedHomeDirectory() throws {
        XCTAssertEqual(
            adapter.defaultConfigPath(),
            tempDir.appendingPathComponent(".config/zed/settings.json")
        )
    }

    // MARK: - Validation

    func testValidateServerKey_valid() {
        XCTAssertEqual(adapter.validateServerKey("github-mcp"), .valid)
        XCTAssertEqual(adapter.validateServerKey("a"), .valid)
        XCTAssertEqual(adapter.validateServerKey("server123"), .valid)
    }

    func testValidateServerKey_invalid() {
        if case .invalid = adapter.validateServerKey("_bad") { } else {
            XCTFail("Expected invalid for key starting with underscore")
        }
        if case .invalid = adapter.validateServerKey("Bad Server") { } else {
            XCTFail("Expected invalid for key with spaces")
        }
    }
}
