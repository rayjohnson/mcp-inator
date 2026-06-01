import XCTest
@testable import mcp_inator

@MainActor
final class CatalogStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        category: CatalogCategory = .productivity,
        editorialRank: Int? = nil,
        alternativeTo: String? = nil,
        relatedApp: String? = nil
    ) -> CatalogEntry {
        CatalogEntry(
            id: id, displayName: id, category: category,
            shortDescription: "desc",
            relatedApp: relatedApp,
            editorialRank: editorialRank,
            alternativeTo: alternativeTo,
            serverKey: id
        )
    }

    private func makeMetrics(
        serverKey: String,
        baseScore: Double = 0,
        isTrending: Bool = false,
        score: Int? = nil
    ) -> ServerMetrics {
        ServerMetrics(serverKey: serverKey, isTrending: isTrending,
                      trendingScore: score, baseScore: baseScore)
    }

    private func makeVM(
        id: String,
        category: CatalogCategory = .productivity,
        editorialRank: Int? = nil,
        alternativeTo: String? = nil,
        baseScore: Double = 0,
        isTrending: Bool = false,
        trendingScore: Int? = nil,
        relatedApp: String? = nil,
        installedApps: Set<String> = []
    ) -> CatalogViewModel {
        let entry = makeEntry(id: id, category: category, editorialRank: editorialRank,
                              alternativeTo: alternativeTo, relatedApp: relatedApp)
        let metrics = makeMetrics(serverKey: id, baseScore: baseScore,
                                  isTrending: isTrending, score: trendingScore)
        return CatalogViewModel(entry: entry, metrics: metrics, installedApps: installedApps)
    }

    // MARK: - sortedEntries

    func testSortedEntriesExcludesAlternatives() {
        let vms = [
            makeVM(id: "primary"),
            makeVM(id: "alt", alternativeTo: "primary")
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.sortedEntries.map(\.id), ["primary"])
    }

    func testSortedEntriesEditorialRankFirst() {
        let vms = [
            makeVM(id: "scored", baseScore: 99),
            makeVM(id: "pinned", editorialRank: 1, baseScore: 1)
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.sortedEntries.map(\.id), ["pinned", "scored"])
    }

    func testSortedEntriesMultipleEditorialRanks() {
        let vms = [
            makeVM(id: "rank2", editorialRank: 2),
            makeVM(id: "rank1", editorialRank: 1),
            makeVM(id: "scored", baseScore: 50)
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.sortedEntries.map(\.id), ["rank1", "rank2", "scored"])
    }

    func testSortedEntriesByDisplayScoreDescending() {
        let vms = [
            makeVM(id: "low", baseScore: 5),
            makeVM(id: "high", baseScore: 30),
            makeVM(id: "mid", baseScore: 15)
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.sortedEntries.map(\.id), ["high", "mid", "low"])
    }

    // MARK: - discoverEntries

    func testDiscoverEntriesExcludesLibraryKeys() {
        let vms = [
            makeVM(id: "in-lib", baseScore: 20),
            makeVM(id: "not-in-lib", baseScore: 10)
        ]
        let store = CatalogStore(viewModels: vms)
        let results = store.discoverEntries(libraryKeys: ["in-lib"])
        XCTAssertEqual(results.map(\.id), ["not-in-lib"])
    }

    func testDiscoverEntriesExcludesEditorialByDefault() {
        let vms = [
            makeVM(id: "editorial", editorialRank: 1, baseScore: 1),
            makeVM(id: "scored1", baseScore: 10),
            makeVM(id: "scored2", baseScore: 8)
        ]
        let store = CatalogStore(viewModels: vms)
        let results = store.discoverEntries(libraryKeys: [])
        XCTAssertFalse(results.map(\.id).contains("editorial"))
    }

    func testDiscoverEntriesFallsBackToEditorialWhenPrimaryEmpty() {
        let vms = [
            makeVM(id: "editorial", editorialRank: 1, baseScore: 1),
            makeVM(id: "scored", baseScore: 10)
        ]
        let store = CatalogStore(viewModels: vms)
        let results = store.discoverEntries(libraryKeys: ["scored"])
        XCTAssertEqual(results.map(\.id), ["editorial"])
    }

    func testDiscoverEntriesCapsAtFive() {
        let vms = (1...8).map { makeVM(id: "e\($0)", baseScore: Double($0)) }
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.discoverEntries(libraryKeys: []).count, 5)
    }

    func testDiscoverEntriesEmptyWhenAllInLibrary() {
        let vms = [makeVM(id: "a"), makeVM(id: "b")]
        let store = CatalogStore(viewModels: vms)
        XCTAssertTrue(store.discoverEntries(libraryKeys: ["a", "b"]).isEmpty)
    }

    // MARK: - alternatives(for:)

    func testAlternativesMatchByRecommendedID() {
        let vms = [
            makeVM(id: "notion-mcp"),
            makeVM(id: "notion-alt1", alternativeTo: "notion-mcp"),
            makeVM(id: "notion-alt2", alternativeTo: "notion-mcp"),
            makeVM(id: "github-mcp")
        ]
        let store = CatalogStore(viewModels: vms)
        let alts = store.alternatives(for: "notion-mcp")
        XCTAssertEqual(Set(alts.map(\.id)), ["notion-alt1", "notion-alt2"])
    }

    func testAlternativesEmptyWhenNoneExist() {
        let store = CatalogStore(viewModels: [makeVM(id: "notion-mcp")])
        XCTAssertTrue(store.alternatives(for: "notion-mcp").isEmpty)
    }

    func testAlternativesDoNotIncludeTopLevelEntry() {
        let vms = [
            makeVM(id: "notion-mcp"),
            makeVM(id: "notion-alt", alternativeTo: "notion-mcp")
        ]
        let store = CatalogStore(viewModels: vms)
        let alts = store.alternatives(for: "notion-mcp")
        XCTAssertFalse(alts.map(\.id).contains("notion-mcp"))
    }

    // MARK: - fetchIfNeeded idempotency

    func testFetchIfNeededCallsClientOnce() async {
        let client = CountingClient()
        let store = CatalogStore(client: client)
        await store.fetchIfNeeded()
        await store.fetchIfNeeded()
        await store.fetchIfNeeded()
        XCTAssertEqual(client.callCount, 1)
    }

    func testFetchIfNeededPopulatesViewModels() async {
        let entry = makeEntry(id: "test-server")
        let client = StubCatalogClient(entries: [entry], metrics: [:])
        let store = CatalogStore(client: client)
        XCTAssertTrue(store.viewModels.isEmpty)
        await store.fetchIfNeeded()
        XCTAssertEqual(store.viewModels.count, 1)
        XCTAssertEqual(store.viewModels[0].id, "test-server")
    }

    func testFetchIfNeededMergesMetrics() async {
        let entry = makeEntry(id: "github-mcp")
        let metrics = makeMetrics(serverKey: "github-mcp", isTrending: true, score: 75)
        let client = StubCatalogClient(entries: [entry], metrics: ["github-mcp": metrics])
        let store = CatalogStore(client: client)
        await store.fetchIfNeeded()
        XCTAssertTrue(store.viewModels[0].isTrending)
        XCTAssertEqual(store.viewModels[0].trendingScore, 75)
    }

    // MARK: - Installed-app boost via displayScore

    func testInstalledAppBoostIncreasesSortOrder() {
        let entry = CatalogEntry(
            id: "github", displayName: "GitHub", category: .developerTools,
            shortDescription: "desc", relatedApp: "GitHub Desktop", serverKey: "github"
        )
        let metricsGH = ServerMetrics(serverKey: "github", baseScore: 10.0)
        let metricsNotion = ServerMetrics(serverKey: "notion", baseScore: 12.0)
        let entryNotion = CatalogEntry(
            id: "notion", displayName: "Notion", category: .productivity,
            shortDescription: "desc", serverKey: "notion"
        )

        // Without app installed: notion (12) sorts above github (10)
        let withoutBoost = [
            CatalogViewModel(entry: entry, metrics: metricsGH, installedApps: []),
            CatalogViewModel(entry: entryNotion, metrics: metricsNotion, installedApps: [])
        ]
        let store1 = CatalogStore(viewModels: withoutBoost)
        XCTAssertEqual(store1.sortedEntries.map(\.id), ["notion", "github"])

        // With app installed: github (10 + 3 = 13) sorts above notion (12)
        let withBoost = [
            CatalogViewModel(entry: entry, metrics: metricsGH, installedApps: ["github desktop"]),
            CatalogViewModel(entry: entryNotion, metrics: metricsNotion, installedApps: [])
        ]
        let store2 = CatalogStore(viewModels: withBoost)
        XCTAssertEqual(store2.sortedEntries.map(\.id), ["github", "notion"])
    }
}

// MARK: - Test doubles

private struct StubCatalogClient: CatalogFetching {
    let entries: [CatalogEntry]
    let metrics: [String: ServerMetrics]
    func fetch() async -> ([CatalogEntry], [String: ServerMetrics]) { (entries, metrics) }
}

private final class CountingClient: CatalogFetching, @unchecked Sendable {
    private(set) var callCount = 0
    func fetch() async -> ([CatalogEntry], [String: ServerMetrics]) {
        callCount += 1
        return ([], [:])
    }
}
