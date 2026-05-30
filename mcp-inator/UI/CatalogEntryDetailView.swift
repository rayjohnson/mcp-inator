import SwiftUI

struct CatalogEntryDetailView: View {
    @EnvironmentObject private var store: ConfigStore

    let vm: CatalogViewModel

    private var entry: CatalogEntry { vm.entry }

    private var libraryMatch: MCPServerConfig? {
        store.configs.first { $0.serverKey == entry.serverKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    Divider()
                    if let note = entry.curatorNote {
                        curatorNoteSection(note)
                        Divider()
                    }
                    commandSection
                    if !entry.envVars.isEmpty || !(entry.requiredArgs?.isEmpty ?? true) {
                        Divider()
                        configSection
                    }
                    if let metrics = vm.metrics {
                        Divider()
                        statsSection(metrics)
                    }
                    if entry.documentationURL != nil || entry.repositoryURL != nil {
                        Divider()
                        linksSection
                    }
                    Spacer(minLength: 16)
                }
                .padding(16)
            }

            Divider()
            actionBar
        }
        .navigationTitle(entry.displayName)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CategoryBadge(category: entry.category)
                if entry.isFirstParty {
                    FirstPartyBadge()
                }
                if vm.isTrending {
                    TrendingBadge(score: vm.trendingScore)
                }
                if libraryMatch != nil {
                    Label("In Library", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Spacer()
            }

            Text(entry.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text(entry.shortDescription)
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                if let stars = vm.starCount {
                    Label(formatStars(stars) + " stars", systemImage: "star")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let dateStr = vm.lastCommitDate, let age = relativeAge(from: dateStr) {
                    Label("Updated \(age)", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let users = vm.userCount, users > 0 {
                    Label("Used by \(users) users", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Curator Note

    private func curatorNoteSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Curator Note", systemImage: "quote.bubble")
                .font(.headline)
            Text(note)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Command

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Run Command", systemImage: "terminal")
                .font(.headline)

            LabeledDetailRow(label: "Command") {
                Text(entry.command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if !entry.args.isEmpty {
                LabeledDetailRow(label: "Arguments") {
                    Text(entry.args.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let requiredArgs = entry.requiredArgs, !requiredArgs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required Arguments")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.top, 4)
                    ForEach(requiredArgs) { arg in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(arg.name)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                if !arg.isRequired {
                                    Text("Optional")
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            Text(arg.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Example: \(arg.placeholder)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }

    // MARK: - Config (env vars)

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Environment Variables", systemImage: "key")
                .font(.headline)

            ForEach(entry.envVars) { envVar in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(envVar.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        if envVar.isRequired {
                            Text("Required")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if envVar.isSensitive {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !envVar.description.isEmpty {
                        Text(envVar.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Stats

    private func statsSection(_ metrics: ServerMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Community", systemImage: "person.3")
                .font(.headline)

            if let summary = metrics.sentimentSummary {
                Text(summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let count = metrics.mentionCount, let days = metrics.periodDays {
                    Text("\(count) mentions in the past \(days) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                if let forks = metrics.forkCount {
                    Label("\(forks) forks", systemImage: "tuningfork")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let issues = metrics.openIssueCount {
                    Label("\(issues) open issues", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Links", systemImage: "link")
                .font(.headline)
            if let docStr = entry.documentationURL, let url = URL(string: docStr) {
                Link(destination: url) {
                    Label("Documentation", systemImage: "book")
                        .font(.body)
                }
            }
            if let repoStr = entry.repositoryURL, let url = URL(string: repoStr) {
                Link(destination: url) {
                    Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.body)
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Spacer()
            if let match = libraryMatch {
                NavigationLink(destination:
                    AddEditConfigView(existing: match)
                        .environmentObject(store)
                ) {
                    Text("Edit in Library")
                }
                .help("Open this server's library entry for editing")
            } else {
                NavigationLink(destination:
                    AddEditConfigView(prefill: MCPServerConfig(from: entry))
                        .environmentObject(store)
                ) {
                    Text("Add to Library")
                }
                .buttonStyle(.borderedProminent)
                .help("Add this server to your library with fields pre-filled from the catalog")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - TrendingBadge

struct TrendingBadge: View {
    let score: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.line.uptrend.xyaxis")
            Text("Trending")
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.orange.opacity(0.15))
        .foregroundColor(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - LabeledDetailRow

private struct LabeledDetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            content()
            Spacer()
        }
    }
}
