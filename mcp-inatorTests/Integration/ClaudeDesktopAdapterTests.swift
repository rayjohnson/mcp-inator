import XCTest
@testable import mcp_inator

// Fixture-specific tests for the Claude Desktop agent definition.
// Generic read/write/drift/remove behavior is covered by FileBasedAdapterTests.
final class ClaudeDesktopAdapterTests: XCTestCase {

    private let adapter = FileBasedAdapter(definition: AdapterRegistry.claudeDesktopDef)
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("claude_desktop_config.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRead_validFixture() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "claude_desktop_config", withExtension: "json")!
        let configs = try adapter.readConfigs(from: fixture)
        XCTAssertEqual(configs.count, 2)
        XCTAssertNotNil(configs["github-mcp"])
    }

    func testRead_preservesUnknownKeys() throws {
        // swiftlint:disable:next force_unwrapping
        let fixture = Bundle(for: type(of: self)).url(forResource: "claude_desktop_config", withExtension: "json")!
        try (try Data(contentsOf: fixture)).write(to: configURL)
        let config = MCPServerConfig(displayName: "New", serverKey: "new-server", command: "/bin/new")
        _ = try adapter.writeConfigs(["new-server": config], to: configURL, expectedExisting: nil)
        // swiftlint:disable:next force_cast
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertNotNil(json["globalShortcut"])
    }
}
