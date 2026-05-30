import XCTest
@testable import mcp_inator

// MARK: - ConnectionTestResult Tests

final class ConnectionTestResultTests: XCTestCase {

    // MARK: isSuccess

    func testIsSuccess_trueOnlyForSuccess() {
        XCTAssertTrue(ConnectionTestResult.success(elapsedSeconds: 1.0, toolCount: 3).isSuccess)
        XCTAssertFalse(ConnectionTestResult.authRequired.isSuccess)
        XCTAssertFalse(ConnectionTestResult.launchError(detail: "x").isSuccess)
        XCTAssertFalse(ConnectionTestResult.protocolError(detail: "x").isSuccess)
        XCTAssertFalse(ConnectionTestResult.timeout.isSuccess)
    }

    // MARK: isWarning

    func testIsWarning_trueOnlyForAuthRequired() {
        XCTAssertTrue(ConnectionTestResult.authRequired.isWarning)
        XCTAssertFalse(ConnectionTestResult.success(elapsedSeconds: 1.0, toolCount: 0).isWarning)
        XCTAssertFalse(ConnectionTestResult.launchError(detail: "x").isWarning)
        XCTAssertFalse(ConnectionTestResult.protocolError(detail: "x").isWarning)
        XCTAssertFalse(ConnectionTestResult.timeout.isWarning)
    }

    // MARK: shortLabel

    func testShortLabel_successSingularTool() {
        let result = ConnectionTestResult.success(elapsedSeconds: 1.0, toolCount: 1)
        XCTAssertEqual(result.shortLabel, "Connected in 1.0s · 1 tool")
    }

    func testShortLabel_successPluralTools() {
        let result = ConnectionTestResult.success(elapsedSeconds: 2.5, toolCount: 5)
        XCTAssertEqual(result.shortLabel, "Connected in 2.5s · 5 tools")
    }

    func testShortLabel_successZeroTools() {
        let result = ConnectionTestResult.success(elapsedSeconds: 0.3, toolCount: 0)
        XCTAssertEqual(result.shortLabel, "Connected in 0.3s · 0 tools")
    }

    func testShortLabel_authRequired() {
        XCTAssertEqual(
            ConnectionTestResult.authRequired.shortLabel,
            "Server reached · auth required (OAuth not testable)"
        )
    }

    func testShortLabel_launchError() {
        XCTAssertEqual(
            ConnectionTestResult.launchError(detail: "No command specified").shortLabel,
            "Could not start: No command specified"
        )
    }

    func testShortLabel_protocolError() {
        XCTAssertEqual(
            ConnectionTestResult.protocolError(detail: "handshake failed").shortLabel,
            "No MCP response: handshake failed"
        )
    }

    func testShortLabel_timeout() {
        XCTAssertEqual(ConnectionTestResult.timeout.shortLabel, "No response after 15 s")
    }
}

// MARK: - ConnectionTester Tests

final class ConnectionTesterTests: XCTestCase {

    private let tester = ConnectionTester()

    // MARK: stdio — guard paths

    func testStdio_emptyCommand_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "Empty", command: "")
        let result = await tester.test(config: config)
        guard case .launchError(let detail) = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
        XCTAssertEqual(detail, "No command specified")
    }

    func testStdio_nonExistentBinary_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "Bad", command: "/nonexistent/binary/that/does/not/exist")
        let result = await tester.test(config: config)
        guard case .launchError = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
    }

    // MARK: HTTP — guard paths

    func testHTTP_emptyURL_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "Empty URL", transportType: .http, url: "")
        let result = await tester.test(config: config)
        guard case .launchError(let detail) = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
        XCTAssertEqual(detail, "Invalid URL")
    }

    func testHTTP_invalidURL_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "Bad URL", transportType: .http, url: "not a url !!!")
        let result = await tester.test(config: config)
        guard case .launchError(let detail) = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
        XCTAssertEqual(detail, "Invalid URL")
    }

    func testHTTP_nonHTTPScheme_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "FTP", transportType: .http, url: "ftp://example.com")
        let result = await tester.test(config: config)
        guard case .launchError(let detail) = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
        XCTAssertEqual(detail, "Invalid URL")
    }

    func testSSE_nonHTTPScheme_returnsLaunchError() async {
        let config = MCPServerConfig(displayName: "SSE bad", transportType: .sse, url: "ws://example.com")
        let result = await tester.test(config: config)
        guard case .launchError(let detail) = result else {
            XCTFail("Expected launchError, got \(result)")
            return
        }
        XCTAssertEqual(detail, "Invalid URL")
    }
}
