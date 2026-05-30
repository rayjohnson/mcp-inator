import XCTest
@testable import mcp_inator

final class GeminiCLIAdapterTests: XCTestCase {

    private let adapter = GeminiCLIAdapter()
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRead_emptyFile() throws {
        XCTAssertTrue(try adapter.readConfigs(from: configURL).isEmpty)
    }

    func testRead_validFixture() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "gemini_config", withExtension: "json")!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        XCTAssertNotNil(configs["github-mcp"])
    }

    func testRead_preservesUnknownKeys() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "gemini_config", withExtension: "json")!
        try (try Data(contentsOf: fixture)).write(to: configURL)
        let config = MCPServerConfig(displayName: "New", serverKey: "new", command: "/bin/new")
        _ = try adapter.writeConfigs(["new": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertNotNil(json["theme"])
    }

    func testWrite_createsFileIfMissing() throws {
        let config = MCPServerConfig(displayName: "Test", serverKey: "test", command: "/bin/test")
        XCTAssertEqual(try adapter.writeConfigs(["test": config], to: configURL, expectedExisting: nil), .success)
    }

    func testWrite_mergesIntoExistingFile() throws {
        let c1 = MCPServerConfig(displayName: "A", serverKey: "a", command: "/bin/a")
        _ = try adapter.writeConfigs(["a": c1], to: configURL, expectedExisting: nil)
        let c2 = MCPServerConfig(displayName: "B", serverKey: "b", command: "/bin/b")
        _ = try adapter.writeConfigs(["b": c2], to: configURL, expectedExisting: nil)
        let configs = try adapter.readConfigs(from: configURL)
        XCTAssertNotNil(configs["a"])
        XCTAssertNotNil(configs["b"])
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
        servers["unmanaged"] = ["command": "/bin/ext"]
        json["mcpServers"] = servers
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]).write(to: configURL)
        XCTAssertEqual(try adapter.writeConfigs(["m": managed], to: configURL, expectedExisting: ["m": managed]), .success)
    }

    func testWrite_atomicOnCrash() throws {
        let ro = tempDir.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: ro.path)
        let target = ro.appendingPathComponent("settings.json")
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

    func testValidateServerKey_rejectsUnderscore() {
        if case .invalid = adapter.validateServerKey("bad_name") { } else { XCTFail("Expected invalid for underscore") }
    }

    func testValidateServerKey_valid() {
        XCTAssertEqual(adapter.validateServerKey("good-name"), .valid)
    }

    func testValidateServerKey_invalid() {
        if case .invalid = adapter.validateServerKey("-leading-hyphen") { } else { XCTFail("Expected invalid") }
    }
}
