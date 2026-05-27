import XCTest
@testable import mcp_inator

final class CatalogEntryTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        id: String = "test/pkg",
        displayName: String = "Test",
        packageType: PackageType = .npm,
        identifier: String = "@test/pkg",
        envVars: [RegistryEnvVar] = []
    ) -> RegistryEntry {
        RegistryEntry(
            id: id, displayName: displayName, description: "desc",
            packageType: packageType, packageIdentifier: identifier,
            remoteURL: nil, remoteType: nil, remoteHeaders: [], envVars: envVars,
            repositoryURL: nil, version: "1.0"
        )
    }

    private func makeRemoteEntry(
        url: String = "https://example.com/mcp",
        remoteType: RemoteTransportType = .streamableHTTP,
        headers: [RegistryEnvVar] = []
    ) -> RegistryEntry {
        RegistryEntry(
            id: "test/remote", displayName: "Remote Test", description: "desc",
            packageType: nil, packageIdentifier: nil,
            remoteURL: url, remoteType: remoteType, remoteHeaders: headers, envVars: [],
            repositoryURL: nil, version: "1.0"
        )
    }

    // MARK: - T052: MCPServerConfig.init(from: RegistryEntry) for stdio

    func testInitFromStdioEntry() {
        let envVar = RegistryEnvVar(
            name: "GITHUB_TOKEN", description: "Personal access token",
            isRequired: true, isSecret: true, valueTemplate: nil
        )
        let entry = makeEntry(
            id: "io.github/github", displayName: "GitHub",
            packageType: .npm, identifier: "@modelcontextprotocol/server-github",
            envVars: [envVar]
        )
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.displayName, "GitHub")
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

    // MARK: - T052: MCPServerConfig.init(from: RegistryEntry) for HTTP

    func testInitFromHTTPEntry() {
        let entry = makeRemoteEntry(url: "https://example.com/mcp", remoteType: .streamableHTTP)
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.transportType, .http)
        XCTAssertEqual(config.url, "https://example.com/mcp")
        XCTAssertEqual(config.command, "")
        XCTAssertTrue(config.args.isEmpty)
        XCTAssertTrue(config.isHTTP)
    }

    func testInitFromSSEEntry() {
        let entry = makeRemoteEntry(url: "https://example.com/sse", remoteType: .sse)
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.transportType, .sse)
        XCTAssertEqual(config.url, "https://example.com/sse")
    }

    // MARK: - T051: isHint set on prefill env vars, not persisted

    func testIsHintSetOnRegistryEnvVars() {
        let entry = makeEntry(envVars: [
            RegistryEnvVar(name: "TOKEN", description: "", isRequired: true, isSecret: true, valueTemplate: nil)
        ])
        let config = MCPServerConfig(from: entry)
        XCTAssertTrue(config.envVars[0].isHint, "Env vars from registry prefill must have isHint=true")
    }

    func testIsHintNotPersisted() throws {
        var ev = EnvVar(key: "TOKEN", value: "")
        ev.isHint = true
        let data = try JSONEncoder().encode(ev)
        let decoded = try JSONDecoder().decode(EnvVar.self, from: data)
        XCTAssertFalse(decoded.isHint, "isHint must not be persisted")
    }

    // MARK: - isSensitive from registry

    func testIsSensitivePropagatedFromRegistry() throws {
        let entry = makeEntry(envVars: [
            RegistryEnvVar(name: "SECRET", description: "", isRequired: true, isSecret: true, valueTemplate: nil),
            RegistryEnvVar(name: "HOST", description: "", isRequired: false, isSecret: false, valueTemplate: nil)
        ])
        let config = MCPServerConfig(from: entry)
        let secret = try XCTUnwrap(config.envVars.first { $0.key == "SECRET" })
        let host = try XCTUnwrap(config.envVars.first { $0.key == "HOST" })
        XCTAssertTrue(secret.isSensitive)
        XCTAssertFalse(host.isSensitive)
    }

    // MARK: - Empty value for registry env vars

    func testEmptyValueForRegistryEnvVars() {
        let entry = makeEntry(envVars: [
            RegistryEnvVar(name: "TOKEN", description: "", isRequired: true, isSecret: true, valueTemplate: nil)
        ])
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.envVars[0].value, "")
    }

    // MARK: - T070: FR-018 hint headers for HTTP entries

    func testHintHeadersForHTTPEntry() {
        let header = RegistryEnvVar(
            name: "Authorization", description: "Bearer token",
            isRequired: true, isSecret: true, valueTemplate: "Bearer {api_key}"
        )
        let entry = makeRemoteEntry(headers: [header])
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.envVars.count, 1)
        XCTAssertEqual(config.envVars[0].key, "Authorization")
        XCTAssertEqual(config.envVars[0].value, "Bearer {api_key}")
        XCTAssertTrue(config.envVars[0].isHint)
    }

    // MARK: - T066: FR-016 env var reference not sensitive

    func testEnvVarReferenceNotSensitive() {
        XCTAssertFalse(EnvVar.defaultSensitivity(for: "${GITHUB_TOKEN}"))
        XCTAssertTrue(EnvVar.defaultSensitivity(for: "literal-secret-value"))
    }
}
