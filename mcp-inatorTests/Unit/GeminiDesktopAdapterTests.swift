import XCTest
@testable import mcp_inator

final class GeminiDesktopAdapterTests: XCTestCase {

    private let adapter = GeminiDesktopAdapter()

    func testAgentType() {
        XCTAssertEqual(adapter.agentType, .geminiDesktop)
    }

    func testIsAppManaged() {
        XCTAssertTrue(adapter.isAppManaged)
    }

    func testReadConfigs_returnsEmpty() throws {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.json")
        let configs = try adapter.readConfigs(from: url)
        XCTAssertTrue(configs.isEmpty)
    }

    func testWriteConfigs_returnsSuccess() throws {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.json")
        let config = MCPServerConfig(displayName: "Test", serverKey: "test", command: "/bin/test")
        let result = try adapter.writeConfigs(["test": config], to: url, expectedExisting: nil)
        XCTAssertEqual(result, .success)
    }

    func testRemoveConfig_returnsSuccess() throws {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.json")
        let result = try adapter.removeConfig(key: "test", from: url, expectedValue: nil)
        XCTAssertEqual(result, .success)
    }

    func testValidateServerKey_alwaysValid() {
        XCTAssertEqual(adapter.validateServerKey("any-key"), .valid)
        XCTAssertEqual(adapter.validateServerKey("UPPER_CASE"), .valid)
        XCTAssertEqual(adapter.validateServerKey(""), .valid)
    }
}
