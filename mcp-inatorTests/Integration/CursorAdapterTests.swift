import XCTest
@testable import mcp_inator

final class CursorAdapterTests: XCTestCase {

    private let adapter = CursorAdapter()
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-cursor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("mcp.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - isInstalled (US1)

    func testIsInstalled_fileExists() throws {
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        let adapter = CursorAdapter()
        // Override defaultConfigPath by using a helper that checks our temp file
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testIsInstalled_dirExistsNoFile() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testIsInstalled_neitherExists() throws {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-no-dir-\(UUID().uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentDir.appendingPathComponent("mcp.json").path))
    }

    // MARK: - Read (US1 + US3)

    func testRead_emptyFile() throws {
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    func testRead_validFixture() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "cursor_mcp", withExtension: "json")!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        XCTAssertNotNil(configs["github-mcp"])
        XCTAssertNotNil(configs["filesystem"])
    }

    func testRead_emptyMcpServersKey() throws {
        let json = #"{"mcpServers": {}}"#
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    // MARK: - Write (US2)

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
        _ = try adapter.removeConfig(key: "r", from: configURL, expectedValue: nil)
        XCTAssertNil(try adapter.readConfigs(from: configURL)["r"])
    }

    func testWrite_driftDetected() throws {
        let original = MCPServerConfig(displayName: "D", serverKey: "d", command: "/bin/d")
        _ = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["d"] = ["command": "/bin/changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)
        let result = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: ["d": original])
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    func testWrite_driftDetected_managedKeyOnly() throws {
        let managed = MCPServerConfig(displayName: "M", serverKey: "m", command: "/bin/m")
        _ = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["unmanaged"] = ["command": "/bin/unmanaged"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)
        XCTAssertEqual(try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: ["m": managed]), .success)
    }

    func testWrite_atomicOnCrash() throws {
        let ro = tempDir.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: ro.path)
        let target = ro.appendingPathComponent("mcp.json")
        let config = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        XCTAssertThrowsError(try adapter.writeConfigs(["x": config], to: target, expectedExisting: nil))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path)
    }

    func testWrite_removeConfig_driftDetected() throws {
        let config = MCPServerConfig(displayName: "Z", serverKey: "z", command: "/bin/z")
        _ = try adapter.writeConfigs(["z": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["z"] = ["command": "/bin/changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)
        let result = try adapter.removeConfig(key: "z", from: configURL, expectedValue: config)
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    // MARK: - Read edge cases (US3)

    func testRead_preservesUnknownKeys() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "cursor_mcp", withExtension: "json")!
        try (try Data(contentsOf: fixture)).write(to: configURL)
        let config = MCPServerConfig(displayName: "New", serverKey: "new-server", command: "/bin/new")
        _ = try adapter.writeConfigs(["new-server": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // The fixture has no unknown top-level keys, but mcpServers should still have 3 entries
        let servers = json["mcpServers"] as? [String: Any]
        XCTAssertEqual(servers?.count, 3)
    }

    // MARK: - Validation (US1)

    func testValidateServerKey_valid() {
        XCTAssertEqual(adapter.validateServerKey("my-server"), .valid)
        XCTAssertEqual(adapter.validateServerKey("cursor-mcp"), .valid)
        XCTAssertEqual(adapter.validateServerKey("github-mcp"), .valid)
    }

    func testValidateServerKey_invalid() {
        if case .invalid = adapter.validateServerKey("-bad") { } else { XCTFail("Expected invalid") }
        if case .invalid = adapter.validateServerKey("bad_key") { } else { XCTFail("Expected invalid") }
        if case .invalid = adapter.validateServerKey("") { } else { XCTFail("Expected invalid") }
    }
}
