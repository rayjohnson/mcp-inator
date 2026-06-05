import Foundation
import CryptoKit

// MARK: - PrivateCatalogPreferences

enum PrivateCatalogPreferences {
    static let urlsChangedNotification = Notification.Name("privateCatalogURLsChanged")

    static var urls: [String] {
        get { UserDefaults.standard.stringArray(forKey: "privateCatalogURLs") ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: "privateCatalogURLs")
            NotificationCenter.default.post(name: urlsChangedNotification, object: nil)
        }
    }
}

// MARK: - PrivateCatalogResponse

struct PrivateCatalogResponse: Codable {
    let tabName: String
    let servers: [CatalogEntry]
}

// MARK: - PrivateCatalogSource

struct PrivateCatalogSource: Identifiable {
    let url: String
    let tabName: String
    let entries: [CatalogViewModel]

    var id: String { url }
}

// MARK: - PrivateCatalogStore

@MainActor
final class PrivateCatalogStore: ObservableObject {
    @Published private(set) var sources: [PrivateCatalogSource] = []

    private let session: URLSession
    private let cacheDir: URL

    init(session: URLSession = .shared, cacheDir: URL = PrivateCatalogStore.defaultCacheDir) {
        self.session = session
        self.cacheDir = cacheDir
        NotificationCenter.default.addObserver(
            forName: PrivateCatalogPreferences.urlsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.fetch() }
        }
    }

    static var defaultCacheDir: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("mcp-inator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Public API

    func fetch() async {
        let deduplicated = deduplicate(PrivateCatalogPreferences.urls)
        var fetched: [PrivateCatalogSource] = []
        await withTaskGroup(of: PrivateCatalogSource?.self) { group in
            for url in deduplicated {
                group.addTask { await self.fetchSource(url: url) }
            }
            for await result in group {
                if let source = result { fetched.append(source) }
            }
        }
        sources = deduplicated.compactMap { url in fetched.first { $0.url == url } }
    }

    // MARK: - Private

    private func fetchSource(url: String) async -> PrivateCatalogSource? {
        guard let requestURL = URL(string: url) else { return nil }
        let request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedSource(url: url)
            }
            let decoded = try JSONDecoder().decode(PrivateCatalogResponse.self, from: data)
            saveCache(decoded, for: url)
            return makeSource(response: decoded, url: url)
        } catch {
            return loadCachedSource(url: url)
        }
    }

    private func loadCachedSource(url: String) -> PrivateCatalogSource? {
        guard let cached = loadCache(for: url) else { return nil }
        return makeSource(response: cached, url: url)
    }

    private func makeSource(response: PrivateCatalogResponse, url: String) -> PrivateCatalogSource {
        let entries = response.servers.map { CatalogViewModel(entry: $0, metrics: nil) }
        return PrivateCatalogSource(url: url, tabName: response.tabName, entries: entries)
    }

    private func deduplicate(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func cacheURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
        return cacheDir.appendingPathComponent("private-catalog-\(hex).json")
    }

    private func saveCache(_ response: PrivateCatalogResponse, for urlString: String) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(response) else { return }
        try? data.write(to: cacheURL(for: urlString), options: .atomic)
    }

    private func loadCache(for urlString: String) -> PrivateCatalogResponse? {
        guard let data = try? Data(contentsOf: cacheURL(for: urlString)) else { return nil }
        return try? JSONDecoder().decode(PrivateCatalogResponse.self, from: data)
    }
}
