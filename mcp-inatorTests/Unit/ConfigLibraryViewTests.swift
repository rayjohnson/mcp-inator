import XCTest
@testable import mcp_inator

final class ConfigLibraryViewTests: XCTestCase {

    // MARK: - Fixtures

    private let github = MCPServerConfig(displayName: "GitHub MCP", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"])
    private let stripe = MCPServerConfig(displayName: "Payments", command: "npx", args: ["stripe-mcp"])
    private let filesystem = MCPServerConfig(displayName: "Filesystem", command: "/usr/local/bin/mcp-filesystem")
    private var httpServer: MCPServerConfig { MCPServerConfig(displayName: "Remote API", transportType: .http, url: "https://api.example.com/mcp") }

    private var allConfigs: [MCPServerConfig] { [github, stripe, filesystem, httpServer] }

    // MARK: - Empty query

    func testEmptyQueryReturnsAll() {
        let result = filterConfigs(allConfigs, query: "")
        XCTAssertEqual(result.count, allConfigs.count)
    }

    // MARK: - Name match

    func testNameMatchReturnsMatchingConfig() {
        let result = filterConfigs(allConfigs, query: "GitHub")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "GitHub MCP")
    }

    func testPartialNameMatch() {
        let result = filterConfigs(allConfigs, query: "pay")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Payments")
    }

    func testNameMatchIsCaseInsensitive() {
        let result = filterConfigs(allConfigs, query: "github")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "GitHub MCP")
    }

    // MARK: - Command match

    func testCommandMatchReturnsAllNpmServers() {
        let result = filterConfigs(allConfigs, query: "npx")
        XCTAssertEqual(result.count, 2)
    }

    func testCommandMatchIsCaseInsensitive() {
        let result = filterConfigs(allConfigs, query: "NPX")
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - HTTP URL match

    func testHTTPURLMatchFindsHttpServer() {
        let result = filterConfigs(allConfigs, query: "example.com")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Remote API")
    }

    func testStdioServerURLNotMatched() {
        // stdio servers have empty url — query against a domain should not surface them
        let result = filterConfigs(allConfigs, query: "api")
        // "Remote API" matches on displayName; no stdio server should match on url
        XCTAssertTrue(result.allSatisfy { $0.displayName.localizedCaseInsensitiveContains("api") || $0.isHTTP })
    }

    // MARK: - No match

    func testNoMatchReturnsEmpty() {
        let result = filterConfigs(allConfigs, query: "zzznomatch")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Existing operations unaffected by filter

    func testFilteredConfigsRetainIdentity() {
        // Filtered results must be the same MCPServerConfig instances (by uuid)
        // so tap-to-edit and swipe-to-delete can still identify the right config.
        let result = filterConfigs(allConfigs, query: "npx")
        XCTAssertTrue(result.allSatisfy { filtered in allConfigs.contains { $0.uuid == filtered.uuid } })
    }

    func testSwipeDeleteConfigReachableAfterFilter() {
        // Verify that a config surfaced by search is present in the full store list
        // (i.e., filtering does not clone or wrap configs — the original object is reachable).
        let result = filterConfigs(allConfigs, query: "stripe")
        XCTAssertEqual(result.count, 1)
        let found = result[0]
        XCTAssertTrue(allConfigs.contains { $0.uuid == found.uuid }, "Filtered config must exist in source list for delete to work")
    }
}
