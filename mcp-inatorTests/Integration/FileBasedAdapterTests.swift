import XCTest
@testable import mcp_inator

// Tests the shared behavior of FileBasedAdapter — read, write, drift, remove.
// Per-adapter test files are trimmed to only what's definition-specific (fixtures, unique validation).
final class FileBasedAdapterTests: XCTestCase {

    // claudeDesktopDef is a representative standard JSON agent
    private let adapter = FileBasedAdapter(definition: AdapterRegistry.claudeDesktopDef)
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-fba-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("config.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Read

    func testRead_missingFile_returnsEmpty() throws {
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    func testRead_emptyMcpServersKey_returnsEmpty() throws {
        try #"{"mcpServers": {}}"#.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    // MARK: - Write

    func testWrite_createsFileIfMissing() throws {
        let config = MCPServerConfig(displayName: "T", serverKey: "t", command: "/bin/t")
        XCTAssertEqual(try adapter.writeConfigs(["t": config], to: configURL, expectedExisting: nil), .success)
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

    func testWrite_preservesUnknownTopLevelKeys() throws {
        let initial: [String: Any] = ["mcpServers": [:] as [String: Any], "extraKey": "value"]
        try JSONSerialization.data(withJSONObject: initial).write(to: configURL)
        let config = MCPServerConfig(displayName: "N", serverKey: "n", command: "/bin/n")
        _ = try adapter.writeConfigs(["n": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertNotNil(json["extraKey"])
    }

    func testWrite_atomicOnPermissionDenied() throws {
        let ro = tempDir.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: ro.path)
        let target = ro.appendingPathComponent("config.json")
        let config = MCPServerConfig(displayName: "X", serverKey: "x", command: "/bin/x")
        XCTAssertThrowsError(try adapter.writeConfigs(["x": config], to: target, expectedExisting: nil))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path)
    }

    // MARK: - Remove

    func testRemove_deletesEntry() throws {
        let config = MCPServerConfig(displayName: "R", serverKey: "r", command: "/bin/r")
        _ = try adapter.writeConfigs(["r": config], to: configURL, expectedExisting: nil)
        _ = try adapter.removeConfig(key: "r", from: configURL, expectedValue: nil)
        XCTAssertNil(try adapter.readConfigs(from: configURL)["r"])
    }

    // MARK: - Drift detection

    func testDrift_onWrite_detectedWhenDiskDiffers() throws {
        let original = MCPServerConfig(displayName: "D", serverKey: "d", command: "/bin/d")
        _ = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["d"] = ["command": "/bin/changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: configURL)
        let result = try adapter.writeConfigs(["d": original], to: configURL, expectedExisting: ["d": original])
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    func testDrift_unmanagedKeyOnDisk_doesNotTriggerDrift() throws {
        let managed = MCPServerConfig(displayName: "M", serverKey: "m", command: "/bin/m")
        _ = try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["unmanaged"] = ["command": "/bin/ext"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: configURL)
        XCTAssertEqual(try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: ["m": managed]), .success)
    }

    func testDrift_onRemove_detectedWhenDiskDiffers() throws {
        let config = MCPServerConfig(displayName: "Z", serverKey: "z", command: "/bin/z")
        _ = try adapter.writeConfigs(["z": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        // swiftlint:disable:next force_cast
        var servers = json["mcpServers"] as! [String: Any]
        servers["z"] = ["command": "/bin/changed"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: configURL)
        let result = try adapter.removeConfig(key: "z", from: configURL, expectedValue: config)
        if case .driftDetected = result { } else { XCTFail("Expected driftDetected") }
    }

    // MARK: - App-managed no-ops

    func testAppManaged_readReturnsEmpty() throws {
        let appAdapter = FileBasedAdapter(definition: AdapterRegistry.geminiDesktopDef)
        XCTAssertTrue(try appAdapter.readConfigs(from: configURL).isEmpty)
    }

    func testAppManaged_writeReturnsSuccess() throws {
        let appAdapter = FileBasedAdapter(definition: AdapterRegistry.geminiDesktopDef)
        let config = MCPServerConfig(displayName: "T", serverKey: "t", command: "/bin/t")
        XCTAssertEqual(try appAdapter.writeConfigs(["t": config], to: configURL, expectedExisting: nil), .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path), "App-managed adapter must not write")
    }

    func testAppManaged_removeReturnsSuccess() throws {
        let appAdapter = FileBasedAdapter(definition: AdapterRegistry.geminiDesktopDef)
        XCTAssertEqual(try appAdapter.removeConfig(key: "t", from: configURL, expectedValue: nil), .success)
    }

    func testAppManaged_validateAlwaysValid() {
        let appAdapter = FileBasedAdapter(definition: AdapterRegistry.geminiDesktopDef)
        XCTAssertEqual(appAdapter.validateServerKey("ANYTHING_GOES"), .valid)
        XCTAssertEqual(appAdapter.validateServerKey(""), .valid)
    }

    // MARK: - Validation

    func testValidate_validKey() {
        XCTAssertEqual(adapter.validateServerKey("my-server"), .valid)
        XCTAssertEqual(adapter.validateServerKey("a"), .valid)
        XCTAssertEqual(adapter.validateServerKey("abc-123"), .valid)
    }

    func testValidate_invalidKey_leadingHyphen() {
        if case .invalid = adapter.validateServerKey("-bad") { } else { XCTFail("Expected invalid") }
    }

    func testValidate_invalidKey_empty() {
        if case .invalid = adapter.validateServerKey("") { } else { XCTFail("Expected invalid") }
    }

    func testValidate_rejectUnderscores_geminiCLI() {
        let gemini = FileBasedAdapter(definition: AdapterRegistry.geminiCLIDef)
        if case .invalid = gemini.validateServerKey("has_underscore") { } else { XCTFail("Expected invalid") }
        XCTAssertEqual(gemini.validateServerKey("no-underscore"), .valid)
    }

    func testValidate_reservedWord_claudeCode() {
        XCTAssertEqual(ClaudeCodeAdapter().validateServerKey("workspace"),
                       .invalid(reason: "\"workspace\" is reserved by Claude Code CLI and cannot be used as a server name."))
        XCTAssertEqual(ClaudeCodeAdapter().validateServerKey("my-server"), .valid)
    }
}
