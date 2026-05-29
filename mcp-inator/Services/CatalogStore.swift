import Foundation
import Combine

// MARK: - CatalogStore

@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var viewModels: [CatalogViewModel] = []
    @Published private(set) var isLoading: Bool = false

    private let client: any CatalogFetching
    private var didFetch = false

    init(client: any CatalogFetching = CatalogClient()) {
        self.client = client
    }

    /// Initializer for unit tests — seeds viewModels directly without any network call.
    init(viewModels: [CatalogViewModel]) {
        self.client = _NullCatalogClient()
        self.viewModels = viewModels
        self.didFetch = true
    }

    // MARK: - Public API

    var trendingEntries: [CatalogViewModel] {
        viewModels
            .filter { $0.isTrending }
            .sorted { ($0.trendingScore ?? 0) > ($1.trendingScore ?? 0) }
    }

    var entriesByCategory: [CatalogCategory: [CatalogViewModel]] {
        Dictionary(grouping: viewModels.filter { !$0.isAlternative }) { vm in
            vm.entry.category
        }
    }

    /// Top-level entries for a category: recommended picks only (no alternativeTo).
    func topLevel(for category: CatalogCategory) -> [CatalogViewModel] {
        entriesByCategory[category] ?? []
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
            CatalogViewModel(entry: entry, metrics: metrics[entry.serverKey])
        }
        isLoading = false
    }
}

// MARK: - _NullCatalogClient

private struct _NullCatalogClient: CatalogFetching {
    func fetch() async -> ([CatalogEntry], [String: ServerMetrics]) { ([], [:]) }
}
