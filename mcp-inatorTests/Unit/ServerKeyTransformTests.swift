import XCTest
@testable import mcp_inator

final class ServerKeyTransformTests: XCTestCase {

    func testBasicTransform() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "GitHub MCP"), "github-mcp")
    }

    func testAllLowercase() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "UPPER CASE"), "upper-case")
    }

    func testStripsNonAlphanumeric() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "Hello! World."), "hello-world")
    }

    func testPreservesHyphens() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "my-server"), "my-server")
    }

    func testTrimsLeadingTrailingHyphens() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "  spaces  "), "spaces")
    }

    func testAlreadyValidKey() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "github-mcp"), "github-mcp")
    }

    func testNumbersPreserved() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "Server 2"), "server-2")
    }

    func testUnicodeStripped() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "café mcp"), "caf-mcp")
    }

    func testEmptyResult() {
        XCTAssertEqual(MCPServerConfig.generateKey(from: "!!!"), "")
    }
}
