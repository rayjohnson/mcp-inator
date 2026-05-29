import XCTest
@testable import mcp_inator

@MainActor
final class CatalogStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        category: CatalogCategory = .productivity,
        alternativeTo: String? = nil
    ) -> CatalogEntry {
        CatalogEntry(
            id: id, displayName: id, category: category,
            shortDescription: "desc", alternativeTo: alternativeTo, serverKey: id
        )
    }

    private func makeMetrics(serverKey: String, isTrending: Bool = false, score: Int? = nil) -> ServerMetrics {
        ServerMetrics(serverKey: serverKey, isTrending: isTrending, trendingScore: score)
    }

    private func makeVM(
        id: String,
        category: CatalogCategory = .productivity,
        alternativeTo: String? = nil,
        isTrending: Bool = false,
        trendingScore: Int? = nil
    ) -> CatalogViewModel {
        let entry = makeEntry(id: id, category: category, alternativeTo: alternativeTo)
        let metrics = makeMetrics(serverKey: id, isTrending: isTrending, score: trendingScore)
        return CatalogViewModel(entry: entry, metrics: metrics)
    }

    // MARK: - trendingEntries

    func testTrendingEntriesReturnsOnlyTrending() {
        let vms = [
            makeVM(id: "a", isTrending: true, trendingScore: 60),
            makeVM(id: "b", isTrending: false),
            makeVM(id: "c", isTrending: true, trendingScore: 80),
        ]
        let store = CatalogStore(viewModels: vms)
        let trending = store.trendingEntries
        XCTAssertEqual(trending.map(\.id), ["c", "a"])
    }

    func testTrendingEntriesEmptyWhenNoneTrending() {
        let vms = [makeVM(id: "a"), makeVM(id: "b")]
        let store = CatalogStore(viewModels: vms)
        XCTAssertTrue(store.trendingEntries.isEmpty)
    }

    func testTrendingEntriesSortedByScoreDescending() {
        let vms = [
            makeVM(id: "low",  isTrending: true, trendingScore: 30),
            makeVM(id: "high", isTrending: true, trendingScore: 90),
            makeVM(id: "mid",  isTrending: true, trendingScore: 55),
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.trendingEntries.map(\.id), ["high", "mid", "low"])
    }

    // MARK: - entriesByCategory

    func testEntriesByCategoryGroupsCorrectly() {
        let vms = [
            makeVM(id: "a", category: .productivity),
            makeVM(id: "b", category: .productivity),
            makeVM(id: "c", category: .codeAndDevelopment),
        ]
        let store = CatalogStore(viewModels: vms)
        XCTAssertEqual(store.entriesByCategory[.productivity]?.count, 2)
        XCTAssertEqual(store.entriesByCategory[.codeAndDevelopment]?.count, 1)
        XCTAssertNil(store.entriesByCategory[.communication])
    }

    func testEntriesByCategoryExcludesAlternatives() {
        let vms = [
            makeVM(id: "primary",     category: .productivity),
            makeVM(id: "alternative", category: .productivity, alternativeTo: "primary"),
        ]
        let store = CatalogStore(viewModels: vms)
        let productivityEntries = store.entriesByCategory[.productivity] ?? []
        XCTAssertEqual(productivityEntries.count, 1)
        XCTAssertEqual(productivityEntries[0].id, "primary")
    }

    // MARK: - topLevel(for:)

    func testTopLevelReturnsNonAlternatives() {
        let vms = [
            makeVM(id: "pick",  category: .productivity),
            makeVM(id: "alt",   category: .productivity, alternativeTo: "pick"),
        ]
        let store = CatalogStore(viewModels: vms)
        let top = store.topLevel(for: .productivity)
        XCTAssertEqual(top.map(\.id), ["pick"])
    }

    func testTopLevelReturnsEmptyForUnknownCategory() {
        let store = CatalogStore(viewModels: [makeVM(id: "a", category: .productivity)])
        XCTAssertTrue(store.topLevel(for: .communication).isEmpty)
    }

    // MARK: - alternatives(for:)

    func testAlternativesMatchByRecommendedID() {
        let vms = [
            makeVM(id: "notion-mcp"),
            makeVM(id: "notion-alt1", alternativeTo: "notion-mcp"),
            makeVM(id: "notion-alt2", alternativeTo: "notion-mcp"),
            makeVM(id: "github-mcp"),
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
            makeVM(id: "notion-alt", alternativeTo: "notion-mcp"),
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
        let client = StubCatalogClient(entries: [entry],
                                       metrics: ["github-mcp": metrics])
        let store = CatalogStore(client: client)
        await store.fetchIfNeeded()
        XCTAssertTrue(store.viewModels[0].isTrending)
        XCTAssertEqual(store.viewModels[0].trendingScore, 75)
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

