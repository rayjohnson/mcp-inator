import XCTest
@testable import mcp_inator

final class MCPServerConfigEquatableTests: XCTestCase {

    // MARK: - envVars order independence
    // Regression: Equatable used array ==, which is order-sensitive. After the
    // 005 registry integration, snapshots stored envVars in registry order while
    // parseMCPConfigs() always sorted them alphabetically — causing a false drift
    // error on every Apply for servers with non-alphabetical env var order.

    func testEnvVars_differentOrder_areEqual() {
        var lhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        lhs.envVars = [EnvVar(key: "Z_KEY", value: "1"), EnvVar(key: "A_KEY", value: "2")]
        var rhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        rhs.envVars = [EnvVar(key: "A_KEY", value: "2"), EnvVar(key: "Z_KEY", value: "1")]
        XCTAssertEqual(lhs, rhs, "Configs with identical envVars in different order must be equal")
    }

    func testEnvVars_differentValues_notEqual() {
        var lhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        lhs.envVars = [EnvVar(key: "TOKEN", value: "abc")]
        var rhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        rhs.envVars = [EnvVar(key: "TOKEN", value: "xyz")]
        XCTAssertNotEqual(lhs, rhs)
    }

    func testEnvVars_differentKeys_notEqual() {
        var lhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        lhs.envVars = [EnvVar(key: "FOO", value: "1")]
        var rhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        rhs.envVars = [EnvVar(key: "BAR", value: "1")]
        XCTAssertNotEqual(lhs, rhs)
    }

    // MARK: - Identity fields excluded from comparison
    // Equatable only compares agent-file fields (transport, command, args, url, envVars).
    // uuid, displayName, serverKey, notes, and timestamps must not affect equality.

    func testIdentityFields_notCompared() {
        let lhs = MCPServerConfig(displayName: "Name A", serverKey: "key-a", command: "/bin/x")
        let rhs = MCPServerConfig(displayName: "Name B", serverKey: "key-b", command: "/bin/x")
        XCTAssertEqual(lhs, rhs)
    }

    // MARK: - Agent-file fields do affect equality

    func testCommand_difference_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", command: "/bin/a")
        let rhs = MCPServerConfig(displayName: "X", command: "/bin/b")
        XCTAssertNotEqual(lhs, rhs)
    }

    func testArgs_difference_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--foo"])
        let rhs = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--bar"])
        XCTAssertNotEqual(lhs, rhs)
    }

    func testArgs_empty_vs_nonempty_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        let rhs = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--flag"])
        XCTAssertNotEqual(lhs, rhs)
    }

    func testTransportType_difference_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", transportType: .http, url: "http://x.com")
        let rhs = MCPServerConfig(displayName: "X", transportType: .sse, url: "http://x.com")
        XCTAssertNotEqual(lhs, rhs)
    }

    func testURL_difference_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", transportType: .http, url: "http://a.com")
        let rhs = MCPServerConfig(displayName: "X", transportType: .http, url: "http://b.com")
        XCTAssertNotEqual(lhs, rhs)
    }

    func testStdioVsHTTP_notEqual() {
        let lhs = MCPServerConfig(displayName: "X", command: "/bin/x")
        let rhs = MCPServerConfig(displayName: "X", transportType: .http, url: "http://x.com")
        XCTAssertNotEqual(lhs, rhs)
    }
}
