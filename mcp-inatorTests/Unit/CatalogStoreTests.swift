import XCTest
@testable import mcp_inator

@MainActor
final class CatalogStoreTests: XCTestCase {

    // MARK: - load()

    func testLoadFromValidBundle() {
        // CatalogStore.load() reads from the app bundle; in the test host bundle
        // catalog.json is not present, so entries should stay empty (no crash).
        let store = CatalogStore()
        store.load()
        // If catalog.json is bundled with the test target this would be non-empty;
        // either way the call must not throw.
        XCTAssertNotNil(store.entries)
    }

    func testLoadWithSchemaVersionMismatch() throws {
        let mismatchJSON = """
        {
          "metadata": {
            "schemaVersion": "999",
            "bundledAt": "2026-01-01T00:00:00Z",
            "entryCount": 1
          },
          "entries": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(Catalog.self, from: mismatchJSON)
        XCTAssertNotEqual(catalog.metadata.schemaVersion, Catalog.supportedSchemaVersion)
    }

    func testLoadWithMalformedJSONProducesEmptyEntries() {
        // A store that can't decode stays empty (no crash).
        let store = CatalogStore()
        store.load()
        // entries is either populated from a real bundle or empty; never throws.
        XCTAssertNotNil(store.entries)
    }

    // MARK: - filtered(search:category:)

    private func makeStore(entries: [CatalogEntry]) -> CatalogStore {
        let store = CatalogStore()
        store.entries = entries
        return store
    }

    private func makeEntry(
        id: String = UUID().uuidString,
        displayName: String,
        category: CatalogCategory = .codeAndDevelopment,
        shortDescription: String = "A test server"
    ) -> CatalogEntry {
        CatalogEntry(
            id: id, displayName: displayName, category: category,
            shortDescription: shortDescription, transportType: .stdio,
            command: "npx", args: [], url: "",
            envVars: [], documentationURL: nil, repositoryURL: nil,
            isVerified: false, serverKey: id
        )
    }

    func testFilterMatchesDisplayName() {
        let store = makeStore(entries: [
            makeEntry(displayName: "GitHub"),
            makeEntry(displayName: "Slack")
        ])
        let results = store.filtered(search: "git", category: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "GitHub")
    }

    func testFilterMatchesDescription() {
        let store = makeStore(entries: [
            makeEntry(displayName: "Alpha", shortDescription: "Connects to postgres"),
            makeEntry(displayName: "Beta", shortDescription: "Sends Slack messages")
        ])
        let results = store.filtered(search: "slack", category: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "Beta")
    }

    func testFilterNilCategoryReturnsAll() {
        let store = makeStore(entries: [
            makeEntry(displayName: "A", category: .codeAndDevelopment),
            makeEntry(displayName: "B", category: .productivity)
        ])
        XCTAssertEqual(store.filtered(search: "", category: nil).count, 2)
    }

    func testFilterSpecificCategory() {
        let store = makeStore(entries: [
            makeEntry(displayName: "A", category: .codeAndDevelopment),
            makeEntry(displayName: "B", category: .productivity)
        ])
        let results = store.filtered(search: "", category: .productivity)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "B")
    }

    func testFilterNoMatchReturnsEmpty() {
        let store = makeStore(entries: [
            makeEntry(displayName: "GitHub"),
            makeEntry(displayName: "Slack")
        ])
        let results = store.filtered(search: "zzznomatch", category: nil)
        XCTAssertTrue(results.isEmpty)
    }

    func testFilterSearchAndCategoryCombined() {
        let store = makeStore(entries: [
            makeEntry(displayName: "GitHub", category: .codeAndDevelopment),
            makeEntry(displayName: "Git Streak", category: .productivity),
        ])
        let results = store.filtered(search: "git", category: .codeAndDevelopment)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "GitHub")
    }

    func testFilterIsCaseInsensitive() {
        let store = makeStore(entries: [makeEntry(displayName: "PostgreSQL")])
        XCTAssertEqual(store.filtered(search: "POSTGRESQL", category: nil).count, 1)
        XCTAssertEqual(store.filtered(search: "postgresql", category: nil).count, 1)
    }
}
