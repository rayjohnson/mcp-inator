import XCTest
@testable import mcp_inator

final class CatalogClientTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempJSON(_ string: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try Data(string.utf8).write(to: url)
        return url
    }

    private var validServersJSON: String {
        """
        {
          "metadata": { "schemaVersion": "2" },
          "entries": [{
            "id": "github-mcp", "displayName": "GitHub MCP",
            "category": "Code & Development", "shortDescription": "desc",
            "transportType": "stdio", "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"],
            "envVars": [], "isVerified": false, "isFirstParty": false, "serverKey": "github-mcp"
          }]
        }
        """
    }

    private var emptyCatalogJSON: String {
        """
        { "metadata": { "schemaVersion": "2" }, "entries": [] }
        """
    }

    /// Builds a cache JSON blob in the shape CatalogClient writes — avoids URLSession for priming.
    private func writeCacheJSON(entries: String = "", serverKey: String = "github-mcp") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-cache.json")
        let cacheJSON = """
        {
          "entries": [\(entries)],
          "metrics": {},
          "fetchedAt": \(Date().timeIntervalSinceReferenceDate)
        }
        """
        try Data(cacheJSON.utf8).write(to: url)
        return url
    }

    private var singleEntryJSON: String {
        """
        {
          "id": "cached-server", "displayName": "Cached Server",
          "category": "Productivity", "shortDescription": "desc",
          "transportType": "stdio", "command": "npx", "args": [],
          "envVars": [], "isVerified": false, "isFirstParty": false, "serverKey": "cached-server"
        }
        """
    }

    private var badURL: URL {
        URL(string: "file:///nonexistent/path/that/does/not/exist.json")!
    }

    // MARK: - Fallback to cache

    func testFallsBackToCacheWhenLiveFails() async throws {
        let cacheURL   = try writeCacheJSON(entries: singleEntryJSON)
        let bundledURL = try writeTempJSON(emptyCatalogJSON)
        let client = CatalogClient(serversURL: badURL, statsURL: badURL,
                                   cacheURL: cacheURL, bundledURL: bundledURL)

        let (entries, _) = await client.fetch()

        XCTAssertEqual(entries.count, 1, "Should return cached entry when live fetch fails")
        XCTAssertEqual(entries[0].id, "cached-server")
    }

    func testCacheFallbackPreservesMetrics() async throws {
        let metricsEntry = """
        {
          "entries": [],
          "metrics": {
            "github-mcp": { "serverKey": "github-mcp", "isArchived": false, "isTrending": true, "starCount": 99 }
          },
          "fetchedAt": \(Date().timeIntervalSinceReferenceDate)
        }
        """
        let cacheURL   = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-cache.json")
        try Data(metricsEntry.utf8).write(to: cacheURL)
        let bundledURL = try writeTempJSON(emptyCatalogJSON)
        let client = CatalogClient(serversURL: badURL, statsURL: badURL,
                                   cacheURL: cacheURL, bundledURL: bundledURL)

        let (_, metrics) = await client.fetch()

        XCTAssertEqual(metrics["github-mcp"]?.starCount, 99)
        XCTAssertTrue(metrics["github-mcp"]?.isTrending ?? false)
    }

    // MARK: - Fallback to bundled

    func testFallsBackToBundledWhenLiveAndCacheFail() async throws {
        let missingCacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-no-cache.json")
        let bundledURL = try writeTempJSON("""
            {
              "metadata": { "schemaVersion": "2" },
              "entries": [{
                "id": "bundled-server", "displayName": "Bundled", "category": "Productivity",
                "shortDescription": "desc", "transportType": "stdio", "command": "npx",
                "args": [], "envVars": [], "isVerified": false, "isFirstParty": false,
                "serverKey": "bundled-server"
              }]
            }
        """)
        let client = CatalogClient(serversURL: badURL, statsURL: badURL,
                                   cacheURL: missingCacheURL, bundledURL: bundledURL)

        let (entries, metrics) = await client.fetch()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "bundled-server")
        XCTAssertTrue(metrics.isEmpty, "Bundled fallback should return no metrics")
    }

    func testBundledFallbackReturnsEmptyWhenBundledMissing() async throws {
        let missingCacheURL   = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-no-cache.json")
        let missingBundledURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-no-bundled.json")
        let client = CatalogClient(serversURL: badURL, statsURL: badURL,
                                   cacheURL: missingCacheURL, bundledURL: missingBundledURL)

        let (entries, metrics) = await client.fetch()

        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(metrics.isEmpty)
    }

    // MARK: - Malformed JSON

    func testMalformedServersJSONFallsBackToBundled() async throws {
        let malformedURL   = try writeTempJSON("{ this is not valid json }")
        let validStatsURL  = try writeTempJSON("""
            { "metadata": { "schemaVersion": "2", "computedAt": "2026-01-01T00:00:00Z" }, "servers": {} }
        """)
        let missingCacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-no-cache.json")
        let bundledURL = try writeTempJSON("""
            {
              "metadata": { "schemaVersion": "2" },
              "entries": [{
                "id": "fallback", "displayName": "Fallback", "category": "Productivity",
                "shortDescription": "desc", "transportType": "stdio", "command": "npx",
                "args": [], "envVars": [], "isVerified": false, "isFirstParty": false,
                "serverKey": "fallback"
              }]
            }
        """)
        let client = CatalogClient(serversURL: malformedURL, statsURL: validStatsURL,
                                   cacheURL: missingCacheURL, bundledURL: bundledURL)

        let (entries, _) = await client.fetch()
        XCTAssertEqual(entries[0].id, "fallback")
    }
}
