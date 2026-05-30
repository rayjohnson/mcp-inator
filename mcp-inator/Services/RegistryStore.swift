import Foundation
import Combine

// MARK: - CategoryCacheState

enum CategoryCacheState: Equatable {
    case uncached
    case loading
    case loaded(fetchedAt: Date, entries: [RegistryEntry])
    case failed(message: String)
}

// MARK: - SearchState

enum SearchState: Equatable {
    case idle
    case searching
    case results([RegistryEntry])
    case localOnly([RegistryEntry])
    case empty
    case failed(message: String)
}

// MARK: - RegistryCacheFile / CategoryCacheEntry

struct CategoryCacheEntry: Codable {
    let fetchedAt: Date
    let entries: [RegistryEntry]
}

struct RegistryCacheFile: Codable {
    let version: Int
    let categories: [String: CategoryCacheEntry]
}

// MARK: - RegistryStore

@MainActor
final class RegistryStore: ObservableObject {
    @Published private(set) var categoryStates: [CatalogCategory: CategoryCacheState]
    @Published private(set) var searchState: SearchState = .idle

    private let client: any RegistryClient
    private let cacheURL: URL

    static var defaultCacheURL: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("mcp-inator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("registry-cache.json")
    }

    init(client: any RegistryClient = URLSessionRegistryClient(),
         cacheURL: URL = RegistryStore.defaultCacheURL) {
        self.client = client
        self.cacheURL = cacheURL
        var states = [CatalogCategory: CategoryCacheState]()
        for category in CatalogCategory.allCases {
            states[category] = .uncached
        }
        self.categoryStates = states
        loadFromCache()
    }

    // MARK: - Category Keywords

    static let categoryKeywords: [CatalogCategory: String] = [
        .codeAndDevelopment: "github",
        .productivity: "notion",
        .dataAndAnalytics: "postgres",
        .communication: "slack",
        .infrastructure: "docker",
        .aiAndLLMs: "openai",
        .webAndBrowser: "browser"
    ]

    // MARK: - Accessors

    func entries(for category: CatalogCategory) -> [RegistryEntry] {
        if case .loaded(_, let entries) = categoryStates[category] ?? .uncached {
            return entries
        }
        return []
    }

    func categoryState(for category: CatalogCategory) -> CategoryCacheState {
        categoryStates[category] ?? .uncached
    }

    var isAllCategoriesUncached: Bool {
        CatalogCategory.allCases.allSatisfy {
            if case .uncached = categoryStates[$0] ?? .uncached { return true }
            return false
        }
    }

    // MARK: - Category Population

    func populateCategories() async {
        var oldStates = [CatalogCategory: CategoryCacheState]()
        for category in CatalogCategory.allCases {
            oldStates[category] = categoryStates[category] ?? .uncached
            categoryStates[category] = .loading
        }

        let capturedClient = client
        let keywords = Self.categoryKeywords

        await withTaskGroup(of: (CatalogCategory, Result<[RegistryEntry], any Error>).self) { group in
            for category in CatalogCategory.allCases {
                guard let keyword = keywords[category] else { continue }
                let cat = category
                group.addTask {
                    do {
                        let entries = try await capturedClient.search(query: keyword, pageSize: 100)
                        return (cat, .success(entries))
                    } catch {
                        return (cat, .failure(error))
                    }
                }
            }

            for await (category, result) in group {
                switch result {
                case .success(let entries):
                    categoryStates[category] = .loaded(fetchedAt: Date(), entries: entries)
                case .failure(let error):
                    let isOffline = (error as? URLError).map {
                        $0.code == .notConnectedToInternet || $0.code == .networkConnectionLost
                    } ?? false

                    let old = oldStates[category] ?? .uncached
                    if case .loaded = old {
                        categoryStates[category] = old
                    } else if isOffline {
                        categoryStates[category] = .uncached
                    } else {
                        categoryStates[category] = .failed(message: error.localizedDescription)
                    }
                }
            }
        }

        saveToCache()
    }

    func refreshCategory(_ category: CatalogCategory) async {
        let old = categoryStates[category] ?? .uncached
        categoryStates[category] = .loading

        let capturedClient = client
        guard let keyword = Self.categoryKeywords[category] else {
            categoryStates[category] = old
            return
        }

        do {
            let entries = try await capturedClient.search(query: keyword, pageSize: 100)
            categoryStates[category] = .loaded(fetchedAt: Date(), entries: entries)
            saveToCache()
        } catch let error as URLError
                where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            if case .loaded = old {
                categoryStates[category] = old
            } else {
                categoryStates[category] = .uncached
            }
        } catch {
            if case .loaded = old {
                categoryStates[category] = old
            } else {
                categoryStates[category] = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Search

    func search(query: String) async {
        searchState = .searching
        do {
            let entries = try await client.search(query: query, pageSize: 100)
            guard !Task.isCancelled else { return }
            searchState = entries.isEmpty ? .empty : .results(entries)
        } catch let error as URLError
                where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            guard !Task.isCancelled else { return }
            searchState = .localOnly(cachedFilter(query: query))
        } catch {
            guard !Task.isCancelled else { return }
            searchState = .failed(message: error.localizedDescription)
        }
    }

    func cancelSearch() {
        searchState = .idle
    }

    // MARK: - Cache I/O

    private func loadFromCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let cacheFile = try? JSONDecoder().decode(RegistryCacheFile.self, from: data) else { return }

        for category in CatalogCategory.allCases {
            if let cached = cacheFile.categories[category.rawValue] {
                categoryStates[category] = .loaded(fetchedAt: cached.fetchedAt, entries: cached.entries)
            }
        }
    }

    private func saveToCache() {
        var dict = [String: CategoryCacheEntry]()
        for (category, state) in categoryStates {
            if case .loaded(let fetchedAt, let entries) = state {
                dict[category.rawValue] = CategoryCacheEntry(fetchedAt: fetchedAt, entries: entries)
            }
        }
        let cacheFile = RegistryCacheFile(version: 1, categories: dict)
        guard let data = try? JSONEncoder().encode(cacheFile) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    private func cachedFilter(query: String) -> [RegistryEntry] {
        var results = [RegistryEntry]()
        for category in CatalogCategory.allCases {
            if case .loaded(_, let entries) = categoryStates[category] ?? .uncached {
                let matching = entries.filter {
                    $0.displayName.localizedCaseInsensitiveContains(query) ||
                    $0.description.localizedCaseInsensitiveContains(query)
                }
                results.append(contentsOf: matching)
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }
}
