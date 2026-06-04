import XCTest
@testable import mcp_inator

// MARK: - URLProtocol stub for URLSessionRegistryClient tests

private class RegistryMockURLProtocol: URLProtocol {
    static nonisolated(unsafe) var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RegistryMockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - RegistryClientTests

@MainActor
final class RegistryClientTests: XCTestCase {

    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "registry-response", withExtension: "json") else {
            throw XCTSkip("registry-response.json fixture not found in test bundle")
        }
        return try Data(contentsOf: url)
    }

    // MARK: - T009: Fixture JSON decode

    func testDecodeFixtureResponse() throws {
        let data = try loadFixture()
        let response = try JSONDecoder().decode(RegistryAPIResponse.self, from: data)
        XCTAssertEqual(response.servers.count, 3)

        let first = response.servers[0]
        XCTAssertTrue(first.meta.official.isLatest)
        XCTAssertEqual(first.server.packages?.first?.environmentVariables?.count, 2)
        XCTAssertEqual(first.server.packages?.first?.environmentVariables?.first?.name, "DATABASE_URL")

        let second = response.servers[1]
        XCTAssertTrue(second.meta.official.isLatest)
        XCTAssertEqual(second.server.remotes?.first?.headers?.count, 1)
        XCTAssertEqual(second.server.remotes?.first?.headers?.first?.name, "Authorization")
        XCTAssertEqual(second.server.remotes?.first?.headers?.first?.value, "Bearer {api_key}")

        let third = response.servers[2]
        XCTAssertTrue(third.meta.official.isLatest)
        XCTAssertNil(third.server.packages)
        XCTAssertNil(third.server.remotes)
    }

    // MARK: - T012: filterLatest

    func testFilterLatest_removesNonLatest() {
        let latest = makeWrapper(name: "a", isLatest: true)
        let notLatest = makeWrapper(name: "b", isLatest: false)
        let result = filterLatest([latest, notLatest])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].server.name, "a")
    }

    func testFilterLatest_keepsAllLatest() {
        let wrappers = [makeWrapper(name: "a", isLatest: true), makeWrapper(name: "b", isLatest: true)]
        XCTAssertEqual(filterLatest(wrappers).count, 2)
    }

    func testFilterLatest_emptyInputReturnsEmpty() {
        XCTAssertTrue(filterLatest([]).isEmpty)
    }

    func testFilterLatest_sameNameMixedLatest() {
        let latest = makeWrapper(name: "x", isLatest: true)
        let old = makeWrapper(name: "x", isLatest: false)
        let result = filterLatest([latest, old])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].meta.official.isLatest)
    }

    // MARK: - T012: deduplicate

    func testDeduplicate_keepsFirstOccurrence() {
        let first = makeWrapper(name: "a", isLatest: true)
        let second = makeWrapper(name: "a", isLatest: true)
        let result = deduplicate([first, second])
        XCTAssertEqual(result.count, 1)
    }

    func testDeduplicate_keepsDifferentNames() {
        let wrappers = [makeWrapper(name: "a", isLatest: true), makeWrapper(name: "b", isLatest: true)]
        XCTAssertEqual(deduplicate(wrappers).count, 2)
    }

    func testDeduplicate_emptyInputReturnsEmpty() {
        XCTAssertTrue(deduplicate([]).isEmpty)
    }

    // MARK: - T015: URLSessionRegistryClient decode-path

    func testURLSessionRegistryClient_decodesAndFilters() async throws {
        let data = try loadFixture()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegistryMockURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = URLSessionRegistryClient(session: session)

        RegistryMockURLProtocol.requestHandler = { _ in
            // swiftlint:disable force_unwrapping
            let response = HTTPURLResponse(
                url: URL(string: "https://registry.modelcontextprotocol.io")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!
            // swiftlint:enable force_unwrapping
            return (response, data)
        }

        let results = try await client.search(query: "test", pageSize: 100)
        // Fixture: 3 entries, all isLatest=true, 2 actionable, 1 not actionable
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - T065: Non-actionable entry filtered by pipeline

    func testNonActionableEntryExcludedFromPipeline() throws {
        let data = try loadFixture()
        let response = try JSONDecoder().decode(RegistryAPIResponse.self, from: data)

        let filtered = filterLatest(response.servers)
        let deduped = deduplicate(filtered)
        let entries = deduped.compactMap { RegistryEntry(raw: $0) }

        // 3 entries in fixture, all isLatest=true, but 1 has no packages/remotes
        XCTAssertEqual(entries.count, 2)

        // Confirm the non-actionable server ID is absent
        let ids = entries.map { $0.id }
        XCTAssertFalse(ids.contains("io.github.testuser/no-transport"))
    }

    // MARK: - Helpers

    private func makeWrapper(name: String, isLatest: Bool) -> RegistryAPIServerWrapper {
        let server = RegistryAPIServer(
            name: name, description: "desc", version: "1.0",
            packages: nil, remotes: nil, repository: nil)
        let meta = RegistryAPIMeta(official: RegistryAPIOfficialMeta(isLatest: isLatest, status: "active"))
        return RegistryAPIServerWrapper(server: server, meta: meta)
    }
}
