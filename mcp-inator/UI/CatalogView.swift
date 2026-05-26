import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var store: ConfigStore

    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory?
    @State private var selectedEntry: CatalogEntry?
    @State private var showDetail = false

    private var filtered: [CatalogEntry] {
        catalogStore.filtered(search: searchText, category: selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search catalog…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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

            Divider()

            // Category filter chips
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

            Divider()

            if filtered.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results")
                        .font(.headline)
                    Text("No catalog entries match your search or filter.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Clear Search") {
                        searchText = ""
                        selectedCategory = nil
                    }
                    Spacer()
                }
                .padding()
            } else {
                List(filtered) { entry in
                    CatalogRow(entry: entry, isInLibrary: store.configs.contains { $0.serverKey == entry.serverKey })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntry = entry
                            showDetail = true
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showDetail) {
            if let entry = selectedEntry {
                NavigationStack {
                    CatalogDetailView(entry: entry)
                        .environmentObject(store)
                }
            }
        }
    }
}

// MARK: - CatalogRow

private struct CatalogRow: View {
    let entry: CatalogEntry
    let isInLibrary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    CategoryBadge(category: entry.category)
                    Spacer()
                    if isInLibrary {
                        Label("In Library", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .labelStyle(.iconOnly)
                            .help("Already in your library")
                    }
                }
                Text(entry.shortDescription)
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
