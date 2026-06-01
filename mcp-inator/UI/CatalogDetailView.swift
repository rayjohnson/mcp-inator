import SwiftUI

struct CatalogDetailView: View {
    @EnvironmentObject private var store: ConfigStore

    let entry: RegistryEntry
    let category: CatalogCategory?

    private var libraryKey: String {
        MCPServerConfig.generateKey(from: entry.displayName)
    }

    private var libraryMatch: MCPServerConfig? {
        store.configs.first { $0.serverKey == libraryKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let cat = category {
                                CategoryBadge(category: cat)
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
                        Text(entry.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Transport
                    let isRemote = entry.transportType != .stdio
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Transport", systemImage: isRemote ? "network" : "terminal")
                            .font(.headline)
                        if isRemote {
                            LabeledRow(label: "URL") {
                                Text(entry.remoteURL ?? "—")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            LabeledRow(label: "Type") {
                                Text(entry.transportType.rawValue.uppercased())
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        } else {
                            LabeledRow(label: "Command") {
                                Text(entry.derivedCommand ?? "—")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if let args = entry.derivedArgs, !args.isEmpty {
                                LabeledRow(label: "Arguments") {
                                    Text(args.joined(separator: " "))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Env vars
                    let envVars = isRemote ? entry.remoteHeaders : entry.envVars
                    if !envVars.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(isRemote ? "Request Headers" : "Environment Variables",
                                      systemImage: "key")
                                    .font(.headline)
                                Spacer()
                            }
                            // Hint notice
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("Suggested from registry — verify with package docs before use")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            ForEach(envVars, id: \.name) { envVar in
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
                                        if envVar.isSecret {
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
                                    if let tmpl = envVar.valueTemplate, !tmpl.isEmpty {
                                        Text("Format: \(tmpl)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }

                    // Links
                    if let repoURL = entry.repositoryURL, let url = URL(string: repoURL) {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Links", systemImage: "link")
                                .font(.headline)
                            Link(destination: url) {
                                Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.body)
                            }
                        }
                    }

                    Spacer(minLength: 16)
                }
                .padding(16)
            }

            Divider()

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
                    .help("Add this server to your library with fields pre-filled from the registry")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationTitle(entry.displayName)
    }
}

// MARK: - Supporting Views

private struct LabeledRow<Content: View>: View {
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

struct CategoryBadge: View {
    let category: CatalogCategory

    var body: some View {
        Text(category.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch category {
        case .developerTools: return .blue
        case .searchWeb:      return .teal
        case .databases:      return .green
        case .productivity:   return .purple
        case .aiMemory:       return .pink
        case .infrastructure: return .gray
        case .finance:        return .orange
        }
    }
}
