import Foundation
import Combine

// MARK: - CatalogStore

@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var viewModels: [CatalogViewModel] = []
    @Published private(set) var isLoading: Bool = false

    private let client: any CatalogFetching
    private let installedApps: Set<String>
    private var didFetch = false

    init(client: any CatalogFetching = CatalogClient()) {
        self.client = client
        self.installedApps = Self.scanInstalledApps()
    }

    /// Initializer for unit tests — seeds viewModels directly without any network call.
    init(viewModels: [CatalogViewModel], installedApps: Set<String> = []) {
        self.client = _NullCatalogClient()
        self.installedApps = installedApps
        self.viewModels = viewModels
        self.didFetch = true
    }

    // MARK: - Public API

    /// All non-alternative entries sorted by editorial rank first, then displayScore descending.
    var sortedEntries: [CatalogViewModel] {
        viewModels
            .filter { !$0.isAlternative }
            .sorted { lhs, rhs in
                switch (lhs.entry.editorialRank, rhs.entry.editorialRank) {
                case let (r1?, r2?): return r1 < r2
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.displayScore > rhs.displayScore
                }
            }
    }

    /// Top non-library servers for the Discover section.
    /// Primary: non-editorial entries not in library, score-ordered.
    /// Fallback: include editorial entries when all non-editorial are in library.
    /// Always returns up to 5; never empty as long as any entry is outside the library.
    func discoverEntries(libraryKeys: Set<String>) -> [CatalogViewModel] {
        let primary = sortedEntries.filter {
            !libraryKeys.contains($0.entry.serverKey) && $0.entry.editorialRank == nil
        }
        if !primary.isEmpty { return Array(primary.prefix(5)) }
        return Array(sortedEntries
            .filter { !libraryKeys.contains($0.entry.serverKey) }
            .prefix(5))
    }

    /// Alternative entries for a given recommended pick's id.
    func alternatives(for recommendedID: String) -> [CatalogViewModel] {
        viewModels.filter { $0.entry.alternativeTo == recommendedID }
    }

    /// Fetch once per session; subsequent calls are no-ops.
    func fetchIfNeeded() async {
        guard !didFetch else { return }
        didFetch = true
        isLoading = true
        let (entries, metrics) = await client.fetch()
        viewModels = entries.map { entry in
            CatalogViewModel(
                entry: entry,
                metrics: metrics[entry.serverKey],
                installedApps: installedApps
            )
        }
        isLoading = false
    }

    // MARK: - Installed-app scan

    static func scanInstalledApps() -> Set<String> {
        let paths = [
            "/Applications",
            (("~/Applications" as NSString).expandingTildeInPath)
        ]
        var names = Set<String>()
        for path in paths {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for item in items where item.hasSuffix(".app") {
                names.insert(item.replacingOccurrences(of: ".app", with: "").lowercased())
            }
        }
        return names
    }
}

// MARK: - _NullCatalogClient

private struct _NullCatalogClient: CatalogFetching {
    func fetch() async -> ([CatalogEntry], [String: ServerMetrics]) { ([], [:]) }
}
