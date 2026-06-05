import XCTest
@testable import mcp_inator

@MainActor
final class PrivateCatalogStoreTests: XCTestCase {

    private var store: PrivateCatalogStore!
    private var session: URLSession!
    private var cacheDir: URL!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests = []
        MockURLProtocol.responsesByURL = [:]
        MockURLProtocol.statusCodesByURL = [:]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateCatalogTests-\(UUID().uuidString)")
        store = PrivateCatalogStore(session: session, cacheDir: cacheDir)
        UserDefaults.standard.removeObject(forKey: "privateCatalogURLs")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "privateCatalogURLs")
        MockURLProtocol.responsesByURL = [:]
        MockURLProtocol.statusCodesByURL = [:]
        try? FileManager.default.removeItem(at: cacheDir)
        super.tearDown()
    }

    // MARK: - Preferences

    func testPreferences_defaultsToEmptyArray() {
        XCTAssertTrue(PrivateCatalogPreferences.urls.isEmpty)
    }

    // MARK: - fetch() — happy path

    func testFetch_noURLs_sourcesIsEmpty() async {
        await store.fetch()
        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_singleURL_producesOneSource() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test Source")
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].tabName, "Test Source")
        XCTAssertEqual(store.sources[0].url, url)
    }

    func testFetch_singleURL_entriesLoaded() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test", serverKey: "my-server")
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertEqual(store.sources[0].entries.count, 1)
        XCTAssertEqual(store.sources[0].entries[0].entry.serverKey, "my-server")
    }

    // MARK: - fetch() — failures

    func testFetch_serverError_silentlySkipped() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.statusCodesByURL[url] = 500
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_badJSON_silentlySkipped() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = Data("not valid json".utf8)
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_invalidURL_silentlySkipped() async {
        PrivateCatalogPreferences.urls = ["not a url!!@#$"]
        await store.fetch()
        XCTAssertTrue(store.sources.isEmpty)
    }

    // MARK: - Cache fallback

    func testFetch_fallsBackToCache_whenNetworkFails() async {
        let url = "https://example.com/catalog.json"

        // First fetch: network succeeds → caches result
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Cached Source")
        PrivateCatalogPreferences.urls = [url]
        await store.fetch()
        XCTAssertEqual(store.sources[0].tabName, "Cached Source")

        // Second fetch: network fails → falls back to cache
        MockURLProtocol.responsesByURL.removeValue(forKey: url)
        MockURLProtocol.statusCodesByURL[url] = 500
        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].tabName, "Cached Source")
    }

    // MARK: - Deduplication and ordering

    func testFetch_deduplicatesURLs() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test")
        PrivateCatalogPreferences.urls = [url, url]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
    }

    func testFetch_preservesConfiguredOrder() async {
        let url1 = "https://example.com/catalog1.json"
        let url2 = "https://example.com/catalog2.json"
        MockURLProtocol.responsesByURL[url1] = makeSourceJSON(tabName: "Source 1")
        MockURLProtocol.responsesByURL[url2] = makeSourceJSON(tabName: "Source 2")
        PrivateCatalogPreferences.urls = [url1, url2]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.sources[0].tabName, "Source 1")
        XCTAssertEqual(store.sources[1].tabName, "Source 2")
    }

    // MARK: - Helpers

    private func makeSourceJSON(tabName: String, serverKey: String = "test-server") -> Data {
        let server: [String: Any] = [
            "id": serverKey,
            "displayName": "Test Server",
            "category": "developer-tools",
            "shortDescription": "A test server.",
            "transportType": "stdio",
            "command": "npx",
            "args": ["-y", "test-pkg"],
            "envVars": [] as [Any],
            "isOfficial": false,
            "serverKey": serverKey
        ]
        let json: [String: Any] = ["tabName": tabName, "servers": [server]]
        return try! JSONSerialization.data(withJSONObject: json)  // swiftlint:disable:this force_try
    }
}
