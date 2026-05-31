import XCTest
@testable import mcp_inator

// Fixture-specific and Gemini-CLI-specific tests.
// Generic read/write/drift/remove behavior is covered by FileBasedAdapterTests.
final class GeminiCLIAdapterTests: XCTestCase {

    private let adapter = FileBasedAdapter(definition: AdapterRegistry.geminiCLIDef)
    private var tempDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-inator-gemini-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configURL = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
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

    func testValidateServerKey_rejectsUnderscore() {
        if case .invalid = adapter.validateServerKey("bad_name") { } else { XCTFail("Expected invalid for underscore") }
        XCTAssertEqual(adapter.validateServerKey("good-name"), .valid)
    }
}
