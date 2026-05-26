import XCTest
@testable import mcp_inator

final class CatalogEntryTests: XCTestCase {

    // MARK: - MCPServerConfig.init(from:) for stdio

    func testInitFromStdioEntry() {
        let entry = CatalogEntry(
            id: "github",
            displayName: "GitHub",
            category: .codeAndDevelopment,
            shortDescription: "GitHub MCP server",
            transportType: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            url: "",
            envVars: [
                CatalogEnvVar(
                    name: "GITHUB_TOKEN",
                    description: "Personal access token",
                    isRequired: true,
                    isSensitive: true,
                    defaultValue: nil
                )
            ],
            documentationURL: "https://example.com/docs",
            repositoryURL: nil,
            isVerified: true,
            serverKey: "github"
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.displayName, "GitHub")
        XCTAssertEqual(config.serverKey, "github")
        XCTAssertEqual(config.transportType, .stdio)
        XCTAssertEqual(config.command, "npx")
        XCTAssertEqual(config.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(config.url, "")
        XCTAssertEqual(config.envVars.count, 1)
        XCTAssertEqual(config.envVars[0].key, "GITHUB_TOKEN")
        XCTAssertTrue(config.envVars[0].isSensitive)
        XCTAssertEqual(config.envVars[0].value, "")
        XCTAssertNil(config.id)
    }

    // MARK: - MCPServerConfig.init(from:) for HTTP

    func testInitFromHTTPEntry() {
        let entry = CatalogEntry(
            id: "my-server",
            displayName: "My Server",
            category: .infrastructure,
            shortDescription: "HTTP test server",
            transportType: .http,
            command: "",
            args: [],
            url: "https://example.com/mcp",
            envVars: [],
            documentationURL: nil,
            repositoryURL: nil,
            isVerified: false,
            serverKey: "my-server"
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.transportType, .http)
        XCTAssertEqual(config.url, "https://example.com/mcp")
        XCTAssertEqual(config.command, "")
        XCTAssertTrue(config.args.isEmpty)
        XCTAssertTrue(config.isHTTP)
    }

    // MARK: - isSensitive propagation

    func testIsSensitivePropagatedFromCatalog() {
        let sensitive = CatalogEnvVar(
            name: "SECRET", description: "", isRequired: true, isSensitive: true, defaultValue: nil
        )
        let notSensitive = CatalogEnvVar(
            name: "HOST", description: "", isRequired: false, isSensitive: false, defaultValue: nil
        )
        let entry = CatalogEntry(
            id: "x", displayName: "X", category: .codeAndDevelopment,
            shortDescription: "", transportType: .stdio,
            command: "cmd", args: [], url: "",
            envVars: [sensitive, notSensitive],
            documentationURL: nil, repositoryURL: nil, isVerified: false, serverKey: "x"
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertTrue(config.envVars.first { $0.key == "SECRET" }!.isSensitive)
        XCTAssertFalse(config.envVars.first { $0.key == "HOST" }!.isSensitive)
    }

    // MARK: - defaultValue usage

    func testDefaultValueUsedWhenPresent() {
        let envVar = CatalogEnvVar(
            name: "REGION", description: "", isRequired: false, isSensitive: false,
            defaultValue: "us-east-1"
        )
        let entry = CatalogEntry(
            id: "y", displayName: "Y", category: .infrastructure,
            shortDescription: "", transportType: .stdio,
            command: "cmd", args: [], url: "",
            envVars: [envVar],
            documentationURL: nil, repositoryURL: nil, isVerified: false, serverKey: "y"
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.envVars[0].value, "us-east-1")
    }

    func testEmptyStringUsedWhenDefaultValueNil() {
        let envVar = CatalogEnvVar(
            name: "TOKEN", description: "", isRequired: true, isSensitive: true,
            defaultValue: nil
        )
        let entry = CatalogEntry(
            id: "z", displayName: "Z", category: .productivity,
            shortDescription: "", transportType: .stdio,
            command: "cmd", args: [], url: "",
            envVars: [envVar],
            documentationURL: nil, repositoryURL: nil, isVerified: false, serverKey: "z"
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.envVars[0].value, "")
    }
}
