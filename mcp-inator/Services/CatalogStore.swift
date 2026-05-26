import Foundation

@MainActor
final class CatalogStore: ObservableObject {
    @Published var entries: [CatalogEntry] = []

    func load() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let catalog = try decoder.decode(Catalog.self, from: data)
            guard catalog.metadata.schemaVersion == Catalog.supportedSchemaVersion else {
                return
            }
            entries = catalog.entries
        } catch {
            entries = []
        }
    }

    func filtered(search: String, category: CatalogCategory?) -> [CatalogEntry] {
        entries.filter { entry in
            let matchesCategory = category == nil || entry.category == category
            let matchesSearch = search.isEmpty
                || entry.displayName.localizedCaseInsensitiveContains(search)
                || entry.shortDescription.localizedCaseInsensitiveContains(search)
            return matchesCategory && matchesSearch
        }
    }
}
