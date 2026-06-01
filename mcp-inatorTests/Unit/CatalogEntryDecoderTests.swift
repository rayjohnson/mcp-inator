import XCTest
@testable import mcp_inator

final class CatalogEntryDecoderTests: XCTestCase {

    // MARK: - Helpers

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }

    private var minimalEntryJSON: String {
        """
        {
          "id": "github-mcp",
          "displayName": "GitHub MCP",
          "category": "developer-tools",
          "shortDescription": "Interact with GitHub via MCP.",
          "transportType": "stdio",
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"],
          "envVars": [],
          "isOfficial": false,
          "serverKey": "github-mcp"
        }
        """
    }

    // MARK: - CatalogEntry required fields

    func testDecodeMinimalEntry() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        XCTAssertEqual(entry.id, "github-mcp")
        XCTAssertEqual(entry.displayName, "GitHub MCP")
        XCTAssertEqual(entry.category, .developerTools)
        XCTAssertEqual(entry.shortDescription, "Interact with GitHub via MCP.")
        XCTAssertEqual(entry.transportType, "stdio")
        XCTAssertEqual(entry.command, "npx")
        XCTAssertEqual(entry.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(entry.serverKey, "github-mcp")
    }

    // MARK: - CatalogEntry optional fields default to nil / false

    func testOptionalFieldsDefaultToNilOrFalse() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        XCTAssertNil(entry.curatorNote)
        XCTAssertNil(entry.url)
        XCTAssertNil(entry.requiredArgs)
        XCTAssertNil(entry.documentationURL)
        XCTAssertNil(entry.repositoryURL)
        XCTAssertNil(entry.alternativeTo)
        XCTAssertNil(entry.relatedApp)
        XCTAssertNil(entry.editorialRank)
        XCTAssertFalse(entry.isOfficial)
    }

    func testMissingBoolsDefaultToFalse() throws {
        let json = """
        {
          "id": "x", "displayName": "X", "category": "productivity",
          "shortDescription": "desc", "transportType": "stdio",
          "command": "npx", "args": [], "envVars": [], "serverKey": "x"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        XCTAssertFalse(entry.isOfficial)
    }

    // MARK: - CatalogEntry full optional fields

    func testDecodeFullEntry() throws {
        let json = """
        {
          "id": "notion-mcp",
          "displayName": "Notion",
          "category": "productivity",
          "shortDescription": "Interact with Notion workspaces.",
          "curatorNote": "Official Notion server.",
          "transportType": "stdio",
          "command": "npx",
          "args": ["-y", "@notionhq/notion-mcp-server"],
          "envVars": [
            { "name": "OPENAPI_MCP_HEADERS", "description": "Auth header", "isRequired": true, "isSensitive": true }
          ],
          "requiredArgs": [
            { "name": "workspace", "description": "Workspace ID", "placeholder": "my-workspace", "isRequired": true }
          ],
          "documentationURL": "https://developers.notion.com",
          "repositoryURL": "https://github.com/makenotion/notion-mcp-server",
          "isOfficial": true,
          "relatedApp": "Notion",
          "editorialRank": 2,
          "alternativeTo": null,
          "serverKey": "notion-mcp"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        XCTAssertEqual(entry.curatorNote, "Official Notion server.")
        XCTAssertTrue(entry.isOfficial)
        XCTAssertEqual(entry.relatedApp, "Notion")
        XCTAssertEqual(entry.editorialRank, 2)
        XCTAssertEqual(entry.envVars.count, 1)
        XCTAssertEqual(entry.envVars[0].name, "OPENAPI_MCP_HEADERS")
        XCTAssertTrue(entry.envVars[0].isRequired)
        XCTAssertTrue(entry.envVars[0].isSensitive)
        XCTAssertEqual(entry.requiredArgs?.count, 1)
        XCTAssertEqual(entry.requiredArgs?[0].name, "workspace")
        XCTAssertEqual(entry.documentationURL, "https://developers.notion.com")
        XCTAssertEqual(entry.repositoryURL, "https://github.com/makenotion/notion-mcp-server")
        XCTAssertNil(entry.alternativeTo)
    }

    func testDecodeAlternativeTo() throws {
        let json = """
        {
          "id": "notion-alt", "displayName": "Notion Alt", "category": "productivity",
          "shortDescription": "desc", "transportType": "stdio", "command": "uvx",
          "args": ["notion-mcp"], "envVars": [], "isOfficial": false,
          "alternativeTo": "notion-mcp", "serverKey": "notion-alt"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        XCTAssertEqual(entry.alternativeTo, "notion-mcp")
    }

    // MARK: - Backward compatibility

    func testDecodesLegacyIsFirstPartyAsIsOfficial() throws {
        let json = """
        {
          "id": "x", "displayName": "X", "category": "productivity",
          "shortDescription": "desc", "transportType": "stdio",
          "command": "npx", "args": [], "envVars": [],
          "isFirstParty": true, "serverKey": "x"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        XCTAssertTrue(entry.isOfficial)
    }

    func testIsOfficialTakesPrecedenceOverIsFirstParty() throws {
        let json = """
        {
          "id": "x", "displayName": "X", "category": "productivity",
          "shortDescription": "desc", "transportType": "stdio",
          "command": "npx", "args": [], "envVars": [],
          "isOfficial": true, "isFirstParty": false, "serverKey": "x"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        XCTAssertTrue(entry.isOfficial)
    }

    func testDecodesLegacyCategoryDisplayStrings() throws {
        let cases: [(String, CatalogCategory)] = [
            ("Code & Development", .developerTools),
            ("Web & Browser", .searchWeb),
            ("Data & Analytics", .databases),
            ("Communication", .productivity),
            ("AI & LLMs", .aiMemory),
            ("Infrastructure", .infrastructure),
            ("Productivity", .productivity)
        ]
        for (categoryString, expected) in cases {
            let json = """
            {
              "id": "x", "displayName": "X", "category": "\(categoryString)",
              "shortDescription": "desc", "transportType": "stdio",
              "command": "npx", "args": [], "envVars": [], "serverKey": "x"
            }
            """
            let entry = try decode(CatalogEntry.self, from: json)
            XCTAssertEqual(entry.category, expected, "'\(categoryString)' should map to \(expected)")
        }
    }

    // MARK: - CatalogFile (servers.json)

    func testDecodeCatalogFile() throws {
        let json = """
        {
          "metadata": { "schemaVersion": "3", "bundledAt": "2026-01-01", "entryCount": 1 },
          "entries": [\(minimalEntryJSON)]
        }
        """
        let file = try decode(CatalogFile.self, from: json)
        XCTAssertEqual(file.metadata.schemaVersion, "3")
        XCTAssertEqual(file.metadata.entryCount, 1)
        XCTAssertEqual(file.entries.count, 1)
        XCTAssertEqual(file.entries[0].id, "github-mcp")
    }

    func testDecodeCatalogFileMetadataOptionals() throws {
        let json = """
        {
          "metadata": { "schemaVersion": "3" },
          "entries": []
        }
        """
        let file = try decode(CatalogFile.self, from: json)
        XCTAssertNil(file.metadata.bundledAt)
        XCTAssertNil(file.metadata.entryCount)
    }

    // MARK: - ServerMetrics

    func testDecodeMinimalMetrics() throws {
        let json = """
        {
          "serverKey": "github-mcp",
          "isArchived": false,
          "isTrending": false
        }
        """
        let metrics = try decode(ServerMetrics.self, from: json)
        XCTAssertEqual(metrics.serverKey, "github-mcp")
        XCTAssertFalse(metrics.isArchived)
        XCTAssertFalse(metrics.isTrending)
        XCTAssertNil(metrics.starCount)
        XCTAssertNil(metrics.trendingScore)
        XCTAssertNil(metrics.sentimentSummary)
        XCTAssertNil(metrics.baseScore)
        XCTAssertNil(metrics.npmWeeklyDownloads)
    }

    func testDecodeFullMetrics() throws {
        let json = """
        {
          "serverKey": "github-mcp",
          "repositoryURL": "https://github.com/foo/bar",
          "starCount": 1234,
          "forkCount": 56,
          "lastCommitDate": "2026-04-01T00:00:00Z",
          "openIssueCount": 7,
          "isArchived": false,
          "githubFetchedAt": "2026-05-01T00:00:00Z",
          "isTrending": true,
          "trendingScore": 82,
          "sentimentSummary": "Highly regarded in the community.",
          "mentionCount": 42,
          "periodDays": 30,
          "sentimentComputedAt": "2026-05-06T00:00:00Z",
          "userCount": 500,
          "enabledCount": 480,
          "weeklyActiveCount": 120,
          "usageAggregatedAt": "2026-05-06T00:00:00Z"
        }
        """
        let metrics = try decode(ServerMetrics.self, from: json)
        XCTAssertEqual(metrics.starCount, 1234)
        XCTAssertEqual(metrics.forkCount, 56)
        XCTAssertEqual(metrics.openIssueCount, 7)
        XCTAssertTrue(metrics.isTrending)
        XCTAssertEqual(metrics.trendingScore, 82)
        XCTAssertEqual(metrics.sentimentSummary, "Highly regarded in the community.")
        XCTAssertEqual(metrics.mentionCount, 42)
        XCTAssertEqual(metrics.periodDays, 30)
        XCTAssertEqual(metrics.userCount, 500)
    }

    func testDecodeSignalFields() throws {
        let json = """
        {
          "serverKey": "github-mcp",
          "isArchived": false,
          "isTrending": false,
          "githubStarsIsShared": true,
          "githubCommits90d": 12,
          "npmWeeklyDownloads": 145230,
          "pypiMonthlyDownloads": null,
          "dockerTotalPulls": 116000,
          "smitheryUseCount": 3873,
          "baseScore": 35.9,
          "signalsRefreshedAt": "2026-06-01T04:12:33Z"
        }
        """
        let metrics = try decode(ServerMetrics.self, from: json)
        XCTAssertTrue(metrics.githubStarsIsShared ?? false)
        XCTAssertEqual(metrics.githubCommits90d, 12)
        XCTAssertEqual(metrics.npmWeeklyDownloads, 145230)
        XCTAssertNil(metrics.pypiMonthlyDownloads)
        XCTAssertEqual(metrics.dockerTotalPulls, 116000)
        XCTAssertEqual(metrics.smitheryUseCount, 3873)
        XCTAssertEqual(metrics.baseScore ?? 0, 35.9, accuracy: 0.01)
        XCTAssertEqual(metrics.signalsRefreshedAt, "2026-06-01T04:12:33Z")
    }

    func testMetricsMissingBoolsDefaultToFalse() throws {
        let json = """
        { "serverKey": "x" }
        """
        let metrics = try decode(ServerMetrics.self, from: json)
        XCTAssertFalse(metrics.isArchived)
        XCTAssertFalse(metrics.isTrending)
    }

    // MARK: - StatsFile (stats.json)

    func testDecodeStatsFile() throws {
        let json = """
        {
          "metadata": { "schemaVersion": "3", "computedAt": "2026-05-01T00:00:00Z" },
          "servers": {
            "github-mcp": { "serverKey": "github-mcp", "starCount": 100, "isArchived": false, "isTrending": true }
          }
        }
        """
        let file = try decode(StatsFile.self, from: json)
        XCTAssertEqual(file.metadata.schemaVersion, "3")
        XCTAssertEqual(file.servers.count, 1)
        XCTAssertEqual(file.servers["github-mcp"]?.starCount, 100)
        XCTAssertTrue(file.servers["github-mcp"]?.isTrending ?? false)
    }

    // MARK: - CatalogViewModel computed properties

    func testViewModelIsTrendingFromMetrics() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        var metrics = try decode(ServerMetrics.self, from: """
            { "serverKey": "github-mcp", "isTrending": true, "trendingScore": 75,
              "isArchived": false }
        """)
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertTrue(vm.isTrending)
        XCTAssertEqual(vm.trendingScore, 75)

        metrics.isTrending = false
        let vmNotTrending = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertFalse(vmNotTrending.isTrending)
    }

    func testViewModelIsAlternative() throws {
        var entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let vm = CatalogViewModel(entry: entry, metrics: nil)
        XCTAssertFalse(vm.isAlternative)

        entry.alternativeTo = "notion-mcp"
        let altVM = CatalogViewModel(entry: entry, metrics: nil)
        XCTAssertTrue(altVM.isAlternative)
    }

    func testViewModelNilMetricsFallbacks() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let vm = CatalogViewModel(entry: entry, metrics: nil)
        XCTAssertFalse(vm.isTrending)
        XCTAssertNil(vm.trendingScore)
        XCTAssertNil(vm.starCount)
        XCTAssertNil(vm.sentimentSummary)
        XCTAssertNil(vm.installCountLabel)
        XCTAssertFalse(vm.isStale)
        XCTAssertFalse(vm.starsIsShared)
        XCTAssertEqual(vm.displayScore, 0.0, accuracy: 0.001)
    }

    func testViewModelDisplayScoreUsesBaseScore() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp", baseScore: 20.5)
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertEqual(vm.displayScore, 20.5, accuracy: 0.001)
    }

    func testViewModelInstalledAppBoost() throws {
        var entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        entry.relatedApp = "GitHub Desktop"
        let metrics = ServerMetrics(serverKey: "github-mcp", baseScore: 10.0)
        let vmWithApp = CatalogViewModel(entry: entry, metrics: metrics,
                                         installedApps: ["github desktop"])
        let vmWithout = CatalogViewModel(entry: entry, metrics: metrics,
                                         installedApps: [])
        XCTAssertEqual(vmWithApp.displayScore, 13.0, accuracy: 0.001)
        XCTAssertEqual(vmWithout.displayScore, 10.0, accuracy: 0.001)
    }

    func testViewModelInstallCountLabel_npm() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp", npmWeeklyDownloads: 145230)
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertEqual(vm.installCountLabel, "145k/wk")
    }

    func testViewModelInstallCountLabel_docker() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp", dockerTotalPulls: 5000)
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertEqual(vm.installCountLabel, "5.0k pulls")
    }

    func testViewModelInstallCountLabel_npmPreferredOverDocker() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp",
                                    npmWeeklyDownloads: 10000, dockerTotalPulls: 5000)
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertTrue(vm.installCountLabel?.hasSuffix("/wk") ?? false)
    }

    func testViewModelIsStaleForOldCommit() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp", lastCommitDate: "2020-01-01T00:00:00Z")
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertTrue(vm.isStale)
    }

    func testViewModelNotStaleForRecentCommit() throws {
        let entry = try decode(CatalogEntry.self, from: minimalEntryJSON)
        let metrics = ServerMetrics(serverKey: "github-mcp", lastCommitDate: "2026-05-01T00:00:00Z")
        let vm = CatalogViewModel(entry: entry, metrics: metrics)
        XCTAssertFalse(vm.isStale)
    }

    // MARK: - MCPServerConfig.init(from: CatalogEntry)

    func testMCPServerConfigFromStdioCatalogEntry() throws {
        let json = """
        {
          "id": "github-mcp", "displayName": "GitHub MCP", "category": "developer-tools",
          "shortDescription": "desc", "transportType": "stdio", "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"],
          "envVars": [
            { "name": "GITHUB_TOKEN", "description": "PAT", "isRequired": true, "isSensitive": true }
          ],
          "isOfficial": false, "serverKey": "github-mcp"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.displayName, "GitHub MCP")
        XCTAssertEqual(config.transportType, .stdio)
        XCTAssertEqual(config.command, "npx")
        XCTAssertEqual(config.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(config.serverKey, "github-mcp")
        XCTAssertEqual(config.envVars.count, 1)
        XCTAssertEqual(config.envVars[0].key, "GITHUB_TOKEN")
        XCTAssertTrue(config.envVars[0].isSensitive)
        XCTAssertTrue(config.envVars[0].isHint)
        XCTAssertEqual(config.envVars[0].value, "")
    }

    func testMCPServerConfigFromHTTPCatalogEntry() throws {
        let json = """
        {
          "id": "remote-mcp", "displayName": "Remote MCP", "category": "infrastructure",
          "shortDescription": "desc", "transportType": "http",
          "command": "", "args": [], "url": "https://example.com/mcp",
          "envVars": [], "isOfficial": false, "serverKey": "remote-mcp"
        }
        """
        let entry = try decode(CatalogEntry.self, from: json)
        let config = MCPServerConfig(from: entry)
        XCTAssertEqual(config.transportType, .http)
        XCTAssertEqual(config.url, "https://example.com/mcp")
        XCTAssertEqual(config.command, "")
        XCTAssertTrue(config.args.isEmpty)
    }
}
