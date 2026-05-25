import SwiftUI

// Shown during first-run discovery (T034) and manual import (T053).
// Categorises on-disk MCP entries as new / exact-match / conflict and lets the user
// approve or skip each one before anything is written to the library.
struct ImportReviewView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    let agent: AgentRecord
    let categories: [(key: String, category: ConfigStore.ImportCategory)]

    // Per-entry decisions: key → user choice
    @State private var decisions: [String: ImportDecision] = [:]
    @State private var errorMessage: String?

    enum ImportDecision {
        case importIt      // use on-disk config
        case keepLibrary   // keep existing library config (conflict only)
        case skip
    }

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    emptyState
                } else {
                    categoryList
                }
            }
            .navigationTitle("Import from \(agent.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import Selected") { applyDecisions() }
                        .disabled(importCount == 0)
                }
            }
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .frame(width: 500, height: 480)
        .onAppear { seedDefaults() }
    }

    private var importCount: Int {
        decisions.values.filter { $0 == .importIt }.count
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No MCP servers found")
                .font(.title2)
            Text("\(agent.displayName) has no MCP server entries in its config file.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var categoryList: some View {
        List {
            let newEntries     = categories.filter { if case .new     = $0.category { true } else { false } }
            let exactMatches   = categories.filter { if case .exactMatch = $0.category { true } else { false } }
            let conflicts      = categories.filter { if case .conflict   = $0.category { true } else { false } }

            if !newEntries.isEmpty {
                Section("New (\(newEntries.count))") {
                    ForEach(newEntries, id: \.key) { entry in
                        if case .new(let config) = entry.category {
                            NewEntryRow(key: entry.key, config: config,
                                        decision: binding(for: entry.key))
                        }
                    }
                }
            }

            if !conflicts.isEmpty {
                Section("Conflicts (\(conflicts.count))") {
                    ForEach(conflicts, id: \.key) { entry in
                        if case .conflict(let library, let onDisk) = entry.category {
                            ConflictRow(key: entry.key, library: library, onDisk: onDisk,
                                        decision: binding(for: entry.key))
                        }
                    }
                }
            }

            if !exactMatches.isEmpty {
                Section("Already in Library (\(exactMatches.count))") {
                    ForEach(exactMatches, id: \.key) { entry in
                        if case .exactMatch(let config) = entry.category {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(config.displayName)
                                        .fontWeight(.medium)
                                    Text(entry.key)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Identical")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Helpers

    private func binding(for key: String) -> Binding<ImportDecision> {
        Binding(
            get: { decisions[key] ?? .skip },
            set: { decisions[key] = $0 }
        )
    }

    private func seedDefaults() {
        for (key, category) in categories {
            switch category {
            case .new:          decisions[key] = .importIt
            case .exactMatch:   decisions[key] = .skip
            case .conflict:     decisions[key] = .skip
            }
        }
    }

    private func applyDecisions() {
        guard let agentId = agent.id else { return }
        var toImport: [(key: String, config: MCPServerConfig)] = []

        for (key, category) in categories {
            switch (decisions[key] ?? .skip, category) {
            case (.importIt, .new(let config)):
                toImport.append((key, config))
            case (.importIt, .conflict(_, let onDisk)):
                toImport.append((key, onDisk))
            case (.keepLibrary, .conflict(let library, _)):
                toImport.append((key, library))
            default:
                break
            }
        }

        do {
            try store.applyImportDecisions(toImport, agentId: agentId)
            dismiss()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - NewEntryRow

private struct NewEntryRow: View {
    let key: String
    let config: MCPServerConfig
    @Binding var decision: ImportReviewView.ImportDecision

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { decision == .importIt },
                set: { decision = $0 ? .importIt : .skip }
            ))
            .labelsHidden()
            VStack(alignment: .leading) {
                Text(config.displayName.isEmpty ? key : config.displayName)
                    .fontWeight(.medium)
                Text("\(config.command) \(config.args.joined(separator: " "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("New")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - ConflictRow

private struct ConflictRow: View {
    let key: String
    let library: MCPServerConfig
    let onDisk: MCPServerConfig
    @Binding var decision: ImportReviewView.ImportDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(library.displayName.isEmpty ? key : library.displayName)
                    .fontWeight(.medium)
                Spacer()
                Text("Conflict")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: 0) {
                ConfigSnippet(label: "Library", config: library, isSelected: decision == .keepLibrary) {
                    decision = .keepLibrary
                }
                ConfigSnippet(label: "Agent File", config: onDisk, isSelected: decision == .importIt) {
                    decision = .importIt
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ConfigSnippet: View {
    let label: String
    let config: MCPServerConfig
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(config.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
