import SwiftUI

struct SharingReviewView: View {
    let servers: [MCPServerConfig]
    let onDismiss: () -> Void

    @State private var entries: [SanitizedServerEntry] = []
    @State private var isSubmitting = false
    @State private var submitError: String?

    private let service = UsageSharingService.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review What You'd Share")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, 20)

                Text("The following server keys and sanitized details would be sent. Toggle off any server you want to exclude permanently.")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.top, 12)

            if entries.isEmpty {
                Text("No eligible servers to share.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($entries) { $entry in
                        SharingEntryRow(entry: $entry)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            if let err = submitError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Submit") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || entries.allSatisfy(\.isExcluded))
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 480)
        .onAppear {
            entries = service.buildEntries(servers: servers)
            let excluded = Set(SharingPreferences.excludedKeys)
            for i in entries.indices {
                entries[i].isExcluded = excluded.contains(entries[i].serverKey)
            }
        }
    }

    private func submit() {
        // Persist exclusion choices before submitting.
        let excludedKeys = entries.filter(\.isExcluded).map(\.serverKey)
        SharingPreferences.excludedKeys = excludedKeys

        guard let report = service.buildPayload(entries: entries) else {
            onDismiss()
            return
        }

        isSubmitting = true
        submitError = nil

        Task {
            do {
                try await service.submit(report: report)
                SharingPreferences.consented = true
                SharingPreferences.shownThisSession = true
                await MainActor.run { onDismiss() }
            } catch {
                service.queueForRetry(report)
                SharingPreferences.consented = true
                SharingPreferences.shownThisSession = true
                await MainActor.run { onDismiss() }
            }
            await MainActor.run { isSubmitting = false }
        }
    }
}

// MARK: - SharingEntryRow

private struct SharingEntryRow: View {
    @Binding var entry: SanitizedServerEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !entry.isExcluded },
                set: { entry.isExcluded = !$0 }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.serverKey)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                if !entry.command.isEmpty {
                    detailLine("command", entry.command)
                }
                if !entry.sanitizedArgs.isEmpty {
                    detailLine("args", entry.sanitizedArgs.joined(separator: " "))
                }
                if !entry.envVarKeys.isEmpty {
                    detailLine("env", entry.envVarKeys.joined(separator: ", "))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(entry.isExcluded ? 0.4 : 1.0)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
