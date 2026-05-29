import Foundation

// MARK: - CatalogClient

actor CatalogClient {

    private let serversURL: URL
    private let statsURL: URL
    private let cacheURL: URL
    private let bundledURL: URL

    static let defaultServersURL = URL(string: "https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/servers.json")!
    static let defaultStatsURL   = URL(string: "https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/stats.json")!

    static var defaultCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("mcp-inator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("catalog-cache.json")
    }

    static var defaultBundledURL: URL {
        Bundle.main.url(forResource: "catalog", withExtension: "json")!
    }

    init(
        serversURL: URL = defaultServersURL,
        statsURL: URL = defaultStatsURL,
        cacheURL: URL = defaultCacheURL,
        bundledURL: URL = defaultBundledURL
    ) {
        self.serversURL = serversURL
        self.statsURL   = statsURL
        self.cacheURL   = cacheURL
        self.bundledURL = bundledURL
    }

    // MARK: - Fetch

    /// Fetches servers.json and stats.json in parallel. Falls back to cache, then bundled catalog.
    func fetch() async -> ([CatalogEntry], [String: ServerMetrics]) {
        do {
            async let serversData = fetchData(from: serversURL)
            async let statsData   = fetchData(from: statsURL)
            let (srvData, stData) = try await (serversData, statsData)

            let entries = try decode(CatalogFile.self, from: srvData).entries
            let metrics = try decode(StatsFile.self, from: stData).servers

            let cached = CatalogCacheFile(entries: entries, metrics: metrics, fetchedAt: Date())
            saveCache(cached)
            return (entries, metrics)
        } catch {
            if let cached = loadCache() {
                return (cached.entries, cached.metrics)
            }
            return (loadBundled(), [:])
        }
    }

    // MARK: - Private helpers

    private func fetchData(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func loadBundled() -> [CatalogEntry] {
        guard let data = try? Data(contentsOf: bundledURL),
              let file = try? decode(CatalogFile.self, from: data) else { return [] }
        return file.entries
    }

    private func loadCache() -> CatalogCacheFile? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let cached = try? decode(CatalogCacheFile.self, from: data) else { return nil }
        return cached
    }

    private func saveCache(_ cache: CatalogCacheFile) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

// MARK: - CatalogCacheFile

private struct CatalogCacheFile: Codable {
    let entries: [CatalogEntry]
    let metrics: [String: ServerMetrics]
    let fetchedAt: Date
}
