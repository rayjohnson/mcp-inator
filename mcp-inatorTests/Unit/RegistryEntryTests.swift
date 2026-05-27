import XCTest
@testable import mcp_inator

final class RegistryEntryTests: XCTestCase {

    // MARK: - T021: deriveCommand

    func testDeriveCommand_npm() {
        let result = RegistryEntry.deriveCommand(packageType: .npm, identifier: "@foo/bar")
        XCTAssertEqual(result.command, "npx")
        XCTAssertEqual(result.args, ["-y", "@foo/bar"])
    }

    func testDeriveCommand_pypi() {
        let result = RegistryEntry.deriveCommand(packageType: .pypi, identifier: "tool")
        XCTAssertEqual(result.command, "uvx")
        XCTAssertEqual(result.args, ["tool"])
    }

    func testDeriveCommand_oci() {
        let result = RegistryEntry.deriveCommand(packageType: .oci, identifier: "image")
        XCTAssertEqual(result.command, "docker")
        XCTAssertEqual(result.args, ["run", "image"])
    }

    // MARK: - T022: displayName(from:)

    func testDisplayName_stripsHyphenMcp() {
        XCTAssertEqual(RegistryEntry.displayName(from: "io.github.YawLabs/postgres-mcp"), "Postgres")
    }

    func testDisplayName_stripsHyphenMcpServer() {
        XCTAssertEqual(RegistryEntry.displayName(from: "com.foo/home-assistant-mcp-server"), "Home Assistant")
    }

    func testDisplayName_noSuffix() {
        XCTAssertEqual(RegistryEntry.displayName(from: "ai.smithery/github"), "Github")
    }

    func testDisplayName_keepsServerSuffix() {
        XCTAssertEqual(RegistryEntry.displayName(from: "io.bar/my-cool-server"), "My Cool Server")
    }

    // MARK: - T067: nil-coercion for optional RegistryAPIEnvVar fields

    func testNilCoercedEnvVarFields() throws {
        let apiVar = RegistryAPIEnvVar(
            name: "MY_KEY",
            description: nil,
            isRequired: nil,
            isSecret: nil,
            format: nil,
            value: nil
        )
        let pkg = RegistryAPIPackage(
            registryType: "npm",
            identifier: "@test/pkg",
            version: nil,
            environmentVariables: [apiVar],
            transport: nil
        )
        let server = RegistryAPIServer(
            name: "io.test/pkg", description: "d", version: "1",
            packages: [pkg], remotes: nil, repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: true, status: "active"))
        let wrapper = RegistryAPIServerWrapper(server: server, meta: meta)

        let entry = try XCTUnwrap(RegistryEntry(raw: wrapper))
        XCTAssertEqual(entry.envVars.count, 1)
        XCTAssertEqual(entry.envVars[0].description, "")
        XCTAssertFalse(entry.envVars[0].isRequired)
        XCTAssertFalse(entry.envVars[0].isSecret)
    }

    func testBlankEnvVarNameDropped() throws {
        let blankVar = RegistryAPIEnvVar(
            name: "  ", description: nil, isRequired: nil, isSecret: nil, format: nil, value: nil)
        let validVar = RegistryAPIEnvVar(
            name: "VALID_KEY", description: nil, isRequired: nil, isSecret: nil, format: nil, value: nil)
        let pkg = RegistryAPIPackage(
            registryType: "npm", identifier: "@t/p", version: nil,
            environmentVariables: [blankVar, validVar], transport: nil)
        let server = RegistryAPIServer(
            name: "io.test/blank", description: "d", version: "1",
            packages: [pkg], remotes: nil, repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: true, status: "active"))
        let wrapper = RegistryAPIServerWrapper(server: server, meta: meta)

        let entry = try XCTUnwrap(RegistryEntry(raw: wrapper))
        XCTAssertEqual(entry.envVars.count, 1)
        XCTAssertEqual(entry.envVars[0].name, "VALID_KEY")
    }

    // MARK: - T068: packages + remotes precedence (stdio wins)

    func testStdioTakesPrecedenceOverRemote() throws {
        let pkg = RegistryAPIPackage(
            registryType: "npm", identifier: "@test/pkg", version: nil,
            environmentVariables: nil, transport: nil)
        let remote = RegistryAPIRemote(
            type: "streamable-http", url: "https://example.com/mcp", headers: nil)
        let server = RegistryAPIServer(
            name: "io.test/both", description: "d", version: "1",
            packages: [pkg], remotes: [remote], repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: true, status: "active"))
        let wrapper = RegistryAPIServerWrapper(server: server, meta: meta)

        let entry = try XCTUnwrap(RegistryEntry(raw: wrapper))
        XCTAssertEqual(entry.transportType, .stdio)
        XCTAssertEqual(entry.packageType, .npm)
        XCTAssertNil(entry.remoteURL)
    }

    // MARK: - isActionable

    func testNonActionableReturnsNil() {
        let server = RegistryAPIServer(
            name: "io.test/empty", description: "d", version: "1",
            packages: nil, remotes: nil, repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: true, status: "active"))
        let wrapper = RegistryAPIServerWrapper(server: server, meta: meta)
        XCTAssertNil(RegistryEntry(raw: wrapper))
    }

    // MARK: - valueTemplate preserved for headers

    func testValueTemplatePreservedForRemoteHeaders() throws {
        let header = RegistryAPIEnvVar(
            name: "Authorization",
            description: "Bearer token",
            isRequired: true,
            isSecret: true,
            format: nil,
            value: "Bearer {api_key}"
        )
        let remote = RegistryAPIRemote(
            type: "streamable-http", url: "https://example.com/mcp", headers: [header])
        let server = RegistryAPIServer(
            name: "io.test/http", description: "d", version: "1",
            packages: nil, remotes: [remote], repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: true, status: "active"))
        let wrapper = RegistryAPIServerWrapper(server: server, meta: meta)

        let entry = try XCTUnwrap(RegistryEntry(raw: wrapper))
        XCTAssertEqual(entry.remoteHeaders[0].valueTemplate, "Bearer {api_key}")
    }
}
