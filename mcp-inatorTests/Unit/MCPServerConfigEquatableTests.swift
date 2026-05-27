import XCTest
@testable import mcp_inator

final class MCPServerConfigEquatableTests: XCTestCase {

    // MARK: - envVars order independence
    // Regression: Equatable used array ==, which is order-sensitive. After the
    // 005 registry integration, snapshots stored envVars in registry order while
    // parseMCPConfigs() always sorted them alphabetically — causing a false drift
    // error on every Apply for servers with non-alphabetical env var order.

    func testEnvVars_differentOrder_areEqual() {
        var a = MCPServerConfig(displayName: "X", command: "/bin/x")
        a.envVars = [EnvVar(key: "Z_KEY", value: "1"), EnvVar(key: "A_KEY", value: "2")]
        var b = MCPServerConfig(displayName: "X", command: "/bin/x")
        b.envVars = [EnvVar(key: "A_KEY", value: "2"), EnvVar(key: "Z_KEY", value: "1")]
        XCTAssertEqual(a, b, "Configs with identical envVars in different order must be equal")
    }

    func testEnvVars_differentValues_notEqual() {
        var a = MCPServerConfig(displayName: "X", command: "/bin/x")
        a.envVars = [EnvVar(key: "TOKEN", value: "abc")]
        var b = MCPServerConfig(displayName: "X", command: "/bin/x")
        b.envVars = [EnvVar(key: "TOKEN", value: "xyz")]
        XCTAssertNotEqual(a, b)
    }

    func testEnvVars_differentKeys_notEqual() {
        var a = MCPServerConfig(displayName: "X", command: "/bin/x")
        a.envVars = [EnvVar(key: "FOO", value: "1")]
        var b = MCPServerConfig(displayName: "X", command: "/bin/x")
        b.envVars = [EnvVar(key: "BAR", value: "1")]
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Identity fields excluded from comparison
    // Equatable only compares agent-file fields (transport, command, args, url, envVars).
    // uuid, displayName, serverKey, notes, and timestamps must not affect equality.

    func testIdentityFields_notCompared() {
        let a = MCPServerConfig(displayName: "Name A", serverKey: "key-a", command: "/bin/x")
        let b = MCPServerConfig(displayName: "Name B", serverKey: "key-b", command: "/bin/x")
        XCTAssertEqual(a, b)
    }

    // MARK: - Agent-file fields do affect equality

    func testCommand_difference_notEqual() {
        let a = MCPServerConfig(displayName: "X", command: "/bin/a")
        let b = MCPServerConfig(displayName: "X", command: "/bin/b")
        XCTAssertNotEqual(a, b)
    }

    func testArgs_difference_notEqual() {
        let a = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--foo"])
        let b = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--bar"])
        XCTAssertNotEqual(a, b)
    }

    func testArgs_empty_vs_nonempty_notEqual() {
        let a = MCPServerConfig(displayName: "X", command: "/bin/x")
        let b = MCPServerConfig(displayName: "X", command: "/bin/x", args: ["--flag"])
        XCTAssertNotEqual(a, b)
    }

    func testTransportType_difference_notEqual() {
        let a = MCPServerConfig(displayName: "X", transportType: .http, url: "http://x.com")
        let b = MCPServerConfig(displayName: "X", transportType: .sse,  url: "http://x.com")
        XCTAssertNotEqual(a, b)
    }

    func testURL_difference_notEqual() {
        let a = MCPServerConfig(displayName: "X", transportType: .http, url: "http://a.com")
        let b = MCPServerConfig(displayName: "X", transportType: .http, url: "http://b.com")
        XCTAssertNotEqual(a, b)
    }

    func testStdioVsHTTP_notEqual() {
        let a = MCPServerConfig(displayName: "X", command: "/bin/x")
        let b = MCPServerConfig(displayName: "X", transportType: .http, url: "http://x.com")
        XCTAssertNotEqual(a, b)
    }
}
