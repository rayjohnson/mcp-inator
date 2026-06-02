import XCTest
@testable import mcp_inator

@MainActor
final class UsageSharingServiceTests: XCTestCase {

    // MARK: - buildEntries sanitization

    func testBuildEntries_excludesPrivateServers() {
        let servers = [
            MCPServerConfig(displayName: "Public", command: "npx", args: []),
            MCPServerConfig(displayName: "Private", command: "npx", args: [], isPrivate: true)
        ]
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: servers)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].serverKey, "public")
    }

    func testBuildEntries_commandIsBasenameOnly() {
        let server = MCPServerConfig(displayName: "Test", command: "/usr/local/bin/npx", args: [])
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: [server])
        XCTAssertEqual(entries[0].command, "npx")
    }

    func testBuildEntries_pathArgsAreRedacted() {
        let server = MCPServerConfig(
            displayName: "Test",
            command: "npx",
            args: ["safe-arg", "/Users/ray/data", "~/documents", "another-safe"]
        )
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: [server])
        XCTAssertEqual(entries[0].sanitizedArgs, ["safe-arg", "<path>", "<path>", "another-safe"])
    }

    func testBuildEntries_envVarKeysOnly() {
        let server = MCPServerConfig(
            displayName: "Test",
            command: "npx",
            args: [],
            envVars: [
                EnvVar(key: "API_KEY", value: "super-secret"),
                EnvVar(key: "TOKEN", value: "also-secret")
            ]
        )
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: [server])
        XCTAssertEqual(entries[0].envVarKeys, ["API_KEY", "TOKEN"])
    }

    func testBuildEntries_emptyCommandProducesEmptyBasename() {
        var server = MCPServerConfig(displayName: "HTTP", serverKey: "http-srv",
                                     transportType: .http, url: "https://example.com")
        _ = server  // suppress unused warning
        // command is empty for HTTP servers; basename("") should stay ""
        let httpServer = MCPServerConfig(displayName: "HTTP", serverKey: "http-srv",
                                         transportType: .http, url: "https://example.com")
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: [httpServer])
        XCTAssertEqual(entries[0].command, "")
    }

    // MARK: - buildPayload exclusion

    func testBuildPayload_excludedKeysNotInPayload() {
        let servers = [
            MCPServerConfig(displayName: "A", command: "npx", args: []),
            MCPServerConfig(displayName: "B", command: "npx", args: []),
            MCPServerConfig(displayName: "C", command: "npx", args: [])
        ]
        let service = UsageSharingService()
        var entries = service.buildEntries(servers: servers)
        entries[1].isExcluded = true  // "b" excluded

        let report = service.buildPayload(entries: entries)
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.serverKeys.contains("b") ?? true)
        XCTAssertEqual(report?.serverKeys.count, 2)
    }

    func testBuildPayload_allExcluded_returnsEmptyKeys() {
        let server = MCPServerConfig(displayName: "A", command: "npx", args: [])
        let service = UsageSharingService()
        var entries = service.buildEntries(servers: [server])
        entries[0].isExcluded = true
        let report = service.buildPayload(entries: entries)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.serverKeys, [])
    }

    func testBuildPayload_schemaVersionIsOne() {
        let server = MCPServerConfig(displayName: "A", command: "npx", args: [])
        let service = UsageSharingService()
        let entries = service.buildEntries(servers: [server])
        let report = service.buildPayload(entries: entries)
        XCTAssertEqual(report?.schemaVersion, "1")
    }

    // MARK: - Retry queue

    func testQueueForRetry_storesPendingReport() {
        let report = UsageReport(serverKeys: ["github-mcp", "filesystem"])
        let service = UsageSharingService()
        service.queueForRetry(report)
        XCTAssertNotNil(SharingPreferences.pendingReport)
        service.clearPending()
    }

    func testClearPending_removesData() {
        let report = UsageReport(serverKeys: ["k"])
        let service = UsageSharingService()
        service.queueForRetry(report)
        service.clearPending()
        XCTAssertNil(SharingPreferences.pendingReport)
        XCTAssertEqual(SharingPreferences.pendingRetryCount, 0)
    }

    func testFlushPending_noData_doesNothing() async {
        SharingPreferences.pendingReport = nil
        let service = UsageSharingService()
        // Should not throw or crash
        await service.flushPendingIfNeeded()
        XCTAssertNil(SharingPreferences.pendingReport)
    }

    func testFlushPending_zeroRetries_clearsData() async {
        let report = UsageReport(serverKeys: ["k"])
        let data = try? JSONEncoder().encode(report)
        SharingPreferences.pendingReport = data
        SharingPreferences.pendingRetryCount = 0

        let service = UsageSharingService()
        await service.flushPendingIfNeeded()
        XCTAssertNil(SharingPreferences.pendingReport)
    }
}
