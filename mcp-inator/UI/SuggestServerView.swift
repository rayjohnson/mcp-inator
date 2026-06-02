import SwiftUI

struct SuggestServerView: View {
    let config: MCPServerConfig
    @Environment(\.dismiss) private var dismiss

    @State private var submitterNote: String = ""
    @State private var isSubmitting = false
    @State private var submittedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            if let url = submittedURL {
                successView(issueURL: url)
            } else {
                formView
            }
        }
        .frame(width: 480, height: 460)
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section {
                Text("Suggest \"\(config.displayName)\" to the public mcp-catalog. " +
                     "An AI pipeline will enrich the submission and open a draft PR for curator review.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section("What will be submitted") {
                submissionPreview
            }

            Section("Why is it useful? (optional)") {
                TextEditor(text: $submitterNote)
                    .frame(minHeight: 60)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Suggest to Catalog")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button("Submit") { submit() }
                }
            }
        }
    }

    // MARK: - Submission preview

    private var submissionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            previewRow(label: "Name", value: config.displayName)
            previewRow(label: "Transport", value: config.transportType.rawValue)

            switch config.transportType {
            case .stdio:
                previewRow(label: "Command", value: config.command)
                if !config.args.isEmpty {
                    previewRow(label: "Args", value: config.args.joined(separator: " "))
                }
            case .http, .sse:
                previewRow(label: "URL", value: config.url)
            }

            if !config.envVars.isEmpty {
                Divider()
                Text("Environment variables")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(config.envVars) { ev in
                    HStack(alignment: .top) {
                        Text(ev.key)
                            .font(.caption.monospaced())
                            .foregroundColor(.primary)
                        Spacer()
                        if ev.isSensitive {
                            Text("(sensitive — not submitted)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else {
                            Text(ev.value.isEmpty ? "(empty)" : ev.value)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if hasSensitiveData {
                Divider()
                Label("Sensitive values (marked orange) are replaced with empty strings before submission.", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var hasSensitiveData: Bool {
        config.envVars.contains { $0.isSensitive }
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Success

    private func successView(issueURL: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("Submission received!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The AI enrichment pipeline is running. A draft PR will appear in the mcp-catalog repo shortly for curator review.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Link("View issue on GitHub", destination: issueURL)
                .buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Suggest to Catalog")
    }

    // MARK: - Submit

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let url = try await CatalogSubmissionService.submit(config, submitterNote: submitterNote)
                await MainActor.run {
                    submittedURL = url
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
