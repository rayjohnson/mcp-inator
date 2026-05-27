import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var registryStore: RegistryStore
    @EnvironmentObject private var store: ConfigStore

    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory?
    @State private var searchTask: Task<Void, Never>?

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if isSearchActive {
                searchResultsView
            } else {
                categoryFilterBar
                Divider()
                categoryBrowseView
            }
        }
        .navigationTitle("Catalog")
        .onChange(of: searchText) { text in
            scheduleSearch(query: text)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search catalog…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    registryStore.cancelSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Category Filter

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(CatalogCategory.allCases) { category in
                    FilterChip(label: category.rawValue, isSelected: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Category Browse

    @ViewBuilder
    private var categoryBrowseView: some View {
        let pairs = browsePairs
        let visibleCategories = selectedCategory.map { [$0] } ?? CatalogCategory.allCases
        let anyLoading = visibleCategories.contains {
            if case .loading = registryStore.categoryState(for: $0) { return true }
            return false
        }

        if pairs.isEmpty && anyLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pairs.isEmpty {
            emptyBrowseState
        } else {
            List(pairs, id: \.entry.id) { item in
                NavigationLink(destination:
                    CatalogDetailView(entry: item.entry, category: item.category)
                        .environmentObject(store)
                ) {
                    CatalogRow(
                        entry: item.entry,
                        category: item.category,
                        isInLibrary: isInLibrary(entry: item.entry)
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            }
            .listStyle(.plain)
        }
    }

    private var browsePairs: [(entry: RegistryEntry, category: CatalogCategory)] {
        let categories = selectedCategory.map { [$0] } ?? CatalogCategory.allCases
        var seen = Set<String>()
        return categories.flatMap { cat in
            registryStore.entries(for: cat).compactMap { entry in
                guard seen.insert(entry.id).inserted else { return nil }
                return (entry, cat)
            }
        }
    }

    @ViewBuilder
    private var emptyBrowseState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No servers loaded")
                .font(.headline)
            Text("Check your connection and try again.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsView: some View {
        switch registryStore.searchState {
        case .idle:
            Color.clear
        case .searching:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results(let entries):
            searchList(entries)
        case .localOnly(let entries):
            VStack(spacing: 0) {
                offlineBanner
                searchList(entries)
            }
        case .empty:
            emptySearchState
        case .failed(let msg):
            searchErrorState(msg)
        }
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("Offline — showing cached results")
                .font(.caption)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }

    private func searchList(_ entries: [RegistryEntry]) -> some View {
        List(entries) { entry in
            NavigationLink(destination:
                CatalogDetailView(entry: entry, category: nil)
                    .environmentObject(store)
            ) {
                CatalogRow(
                    entry: entry,
                    category: nil,
                    isInLibrary: isInLibrary(entry: entry)
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No results")
                .font(.headline)
            Text("No servers matched \"\(searchText)\"")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Clear Search") {
                searchText = ""
            }
            Spacer()
        }
        .padding()
    }

    private func searchErrorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Search failed")
                .font(.headline)
            Text(msg)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func isInLibrary(entry: RegistryEntry) -> Bool {
        let key = MCPServerConfig.generateKey(from: entry.displayName)
        return store.configs.contains { $0.serverKey == key }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            registryStore.cancelSearch()
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await registryStore.search(query: trimmed)
        }
    }
}

// MARK: - CatalogRow

private struct CatalogRow: View {
    let entry: RegistryEntry
    let category: CatalogCategory?
    let isInLibrary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if let cat = category {
                        CategoryBadge(category: cat)
                    }
                    Spacer()
                    if isInLibrary {
                        Label("In Library", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .labelStyle(.iconOnly)
                            .help("Already in your library")
                    }
                }
                Text(entry.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.borderless)
    }
}
