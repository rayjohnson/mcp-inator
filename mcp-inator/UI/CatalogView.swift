import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var store: ConfigStore

    @Binding var selectedEntry: CatalogViewModel?
    let isCompact: Bool

    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory?

    var body: some View {
        VStack(spacing: 0) {
            if catalogStore.isLoading && catalogStore.viewModels.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResultsView
            } else {
                categoryFilterBar
                Divider()
                browseView
            }
        }
        .navigationTitle("Catalog")
        .searchable(text: $searchText, prompt: "Search catalog…")
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

    // MARK: - Browse

    @ViewBuilder
    private var browseView: some View {
        let trending = catalogStore.trendingEntries
        let categories = selectedCategory.map { [$0] } ?? CatalogCategory.allCases

        if catalogStore.viewModels.isEmpty {
            emptyState
        } else {
            List {
                if selectedCategory == nil && !trending.isEmpty {
                    trendingSection(trending)
                }
                ForEach(categories, id: \.self) { cat in
                    let entries = catalogStore.topLevel(for: cat)
                    if !entries.isEmpty {
                        Section(cat.rawValue) {
                            ForEach(entries) { vm in
                                entryRow(vm, showCategory: false)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func trendingSection(_ entries: [CatalogViewModel]) -> some View {
        Section {
            ForEach(entries) { vm in
                entryRow(vm, showCategory: true)
            }
        } header: {
            Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func entryRow(_ vm: CatalogViewModel, showCategory: Bool) -> some View {
        let alts = catalogStore.alternatives(for: vm.entry.id)
        if alts.isEmpty {
            if isCompact {
                NavigationLink(destination: CatalogEntryDetailView(vm: vm).environmentObject(store)) {
                    CatalogRow(vm: vm, showCategory: showCategory, isInLibrary: isInLibrary(vm))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            } else {
                CatalogRow(vm: vm, showCategory: showCategory, isInLibrary: isInLibrary(vm))
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedEntry = vm }
                    .listRowBackground(
                        selectedEntry?.id == vm.id ? Color.accentColor.opacity(0.15) : Color.clear
                    )
            }
        } else {
            AlternativesRow(
                vm: vm,
                alternatives: alts,
                showCategory: showCategory,
                isInLibrary: isInLibrary(vm),
                altIsInLibrary: { isInLibrary($0) },
                store: store,
                isCompact: isCompact,
                onSelect: { selectedEntry = $0 }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            .listRowBackground(
                !isCompact && (selectedEntry?.id == vm.id || alts.contains(where: { selectedEntry?.id == $0.id }))
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsView: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let results = catalogStore.viewModels.filter { vm in
            vm.entry.displayName.lowercased().contains(query) ||
            vm.entry.shortDescription.lowercased().contains(query) ||
            (vm.entry.curatorNote?.lowercased().contains(query) ?? false)
        }

        if results.isEmpty {
            emptySearchState
        } else {
            List(results) { vm in
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
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
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

// MARK: - CatalogRow

struct CatalogRow: View {
    let vm: CatalogViewModel
    let showCategory: Bool
    let isInLibrary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vm.entry.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if vm.entry.isFirstParty {
                        FirstPartyBadge()
                    }
                    if showCategory {
                        CategoryBadge(category: vm.entry.category)
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

                HStack(spacing: 8) {
                    if let stars = vm.starCount {
                        Label(formatStars(stars), systemImage: "star")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let dateStr = vm.lastCommitDate, let age = relativeAge(from: dateStr) {
                        Text(age)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(vm.entry.shortDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let note = vm.entry.curatorNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AlternativesRow

private struct AlternativesRow: View {
    let vm: CatalogViewModel
    let alternatives: [CatalogViewModel]
    let showCategory: Bool
    let isInLibrary: Bool
    let altIsInLibrary: (CatalogViewModel) -> Bool
    let store: ConfigStore
    let isCompact: Bool
    let onSelect: (CatalogViewModel) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCompact {
                NavigationLink(destination: CatalogEntryDetailView(vm: vm).environmentObject(store)) {
                    CatalogRow(vm: vm, showCategory: showCategory, isInLibrary: isInLibrary)
                }
            } else {
                CatalogRow(vm: vm, showCategory: showCategory, isInLibrary: isInLibrary)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(vm) }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("\(alternatives.count) alternative\(alternatives.count == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .foregroundColor(.accentColor)
                .padding(.top, 2)
                .padding(.leading, 4)
            }
            .buttonStyle(.borderless)

            if expanded {
                ForEach(alternatives) { alt in
                    if isCompact {
                        NavigationLink(destination: CatalogEntryDetailView(vm: alt).environmentObject(store)) {
                            CatalogRow(vm: alt, showCategory: false, isInLibrary: altIsInLibrary(alt))
                                .padding(.leading, 16)
                        }
                        .padding(.top, 4)
                    } else {
                        CatalogRow(vm: alt, showCategory: false, isInLibrary: altIsInLibrary(alt))
                            .padding(.leading, 16)
                            .padding(.top, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(alt) }
                    }
                }
            }
        }
    }
}

// MARK: - FirstPartyBadge

struct FirstPartyBadge: View {
    var body: some View {
        Text("Official")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
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

// MARK: - Formatting helpers

func formatStars(_ count: Int) -> String {
    if count >= 1000 {
        let k = Double(count) / 1000.0
        return String(format: k >= 10 ? "%.0fK" : "%.1fK", k)
    }
    return "\(count)"
}

func relativeAge(from iso8601: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso8601)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso8601)
    }
    guard let date else { return nil }
    let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    switch days {
    case 0:      return "today"
    case 1:      return "yesterday"
    case 2...6:  return "\(days) days ago"
    case 7...13: return "1 week ago"
    case 14...29: return "\(days / 7) weeks ago"
    case 30...59: return "1 month ago"
    case 60...364: return "\(days / 30) months ago"
    default:     return "\(days / 365) year\(days / 365 == 1 ? "" : "s") ago"
    }
}
