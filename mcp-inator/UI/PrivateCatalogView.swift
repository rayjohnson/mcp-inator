import SwiftUI

struct PrivateCatalogView: View {
    @EnvironmentObject private var store: ConfigStore

    let entries: [CatalogViewModel]
    let tabTitle: String
    let isCompact: Bool
    @Binding var selectedEntry: CatalogViewModel?

    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory?

    private var usedCategories: [CatalogCategory] {
        let present = Set(entries.map(\.entry.category))
        return CatalogCategory.allCases.filter { present.contains($0) }
    }

    private var sortedEntries: [CatalogViewModel] {
        entries.sorted {
            $0.entry.displayName.localizedCaseInsensitiveCompare($1.entry.displayName) == .orderedAscending
        }
    }

    private var visibleEntries: [CatalogViewModel] {
        let byCategory: [CatalogViewModel]
        if let cat = selectedCategory {
            byCategory = sortedEntries.filter { $0.entry.category == cat }
        } else {
            byCategory = sortedEntries
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return byCategory }
        return byCategory.filter { vm in
            vm.entry.displayName.lowercased().contains(query) ||
            vm.entry.shortDescription.lowercased().contains(query) ||
            vm.entry.category.label.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && visibleEntries.isEmpty {
                emptySearchState
            } else {
                categoryFilterBar
                Divider()
                entryList
            }
        }
        .navigationTitle(tabTitle)
        .searchable(text: $searchText, prompt: "Search \(tabTitle)\u{2026}")
    }

    // MARK: - Category filter bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(usedCategories) { category in
                    FilterChip(label: category.label, isSelected: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        List {
            Section {
                ForEach(visibleEntries) { vm in entryRow(vm) }
            } header: {
                Text("All Servers")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func entryRow(_ vm: CatalogViewModel) -> some View {
        if isCompact {
            NavigationLink(destination: CatalogEntryDetailView(vm: vm).environmentObject(store)) {
                CatalogRow(vm: vm, showCategory: true, isInLibrary: isInLibrary(vm))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
        } else {
            CatalogRow(vm: vm, showCategory: true, isInLibrary: isInLibrary(vm))
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .contentShape(Rectangle())
                .onTapGesture { selectedEntry = vm }
                .listRowBackground(
                    selectedEntry?.id == vm.id ? Color.accentColor.opacity(0.15) : Color.clear
                )
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "building.2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No servers in this catalog")
                .font(.headline)
            Text("The catalog may still be loading, or the URL returned no servers.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

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
            Button("Clear Search") { searchText = "" }
            Spacer()
        }
        .padding()
    }

    private func isInLibrary(_ vm: CatalogViewModel) -> Bool {
        store.configs.contains { $0.serverKey == vm.entry.serverKey }
    }
}
