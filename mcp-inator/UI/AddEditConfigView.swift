import SwiftUI

struct AddEditConfigView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    let existing: MCPServerConfig?

    @State private var displayName: String
    @State private var serverKey: String
    @State private var serverKeyEdited: Bool
    @State private var transportType: TransportType
    // stdio fields
    @State private var command: String
    @State private var args: [String]
    @State private var newArg: String = ""
    // http/sse fields
    @State private var url: String
    // shared: env vars (stdio) or headers (http/sse)
    @State private var envVars: [EnvVar]
    @State private var newEnvKey: String = ""
    @State private var newEnvValue: String = ""
    @State private var notes: String
    @State private var revealedEnvIds: Set<UUID> = []
    @State private var validationError: String?
    @State private var showPropagation = false
    @State private var savedConfig: MCPServerConfig?
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    private let tester = ConnectionTester()

    init(existing: MCPServerConfig? = nil) {
        self.existing = existing
        _displayName     = State(initialValue: existing?.displayName ?? "")
        _serverKey       = State(initialValue: existing?.serverKey ?? "")
        _serverKeyEdited = State(initialValue: existing != nil)
        _transportType   = State(initialValue: existing?.transportType ?? .stdio)
        _command         = State(initialValue: existing?.command ?? "")
        _args            = State(initialValue: existing?.args ?? [])
        _url             = State(initialValue: existing?.url ?? "")
        _envVars         = State(initialValue: existing?.envVars ?? [])
        _notes           = State(initialValue: existing?.notes ?? "")
    }

    init(prefill: MCPServerConfig) {
        self.existing = nil
        _displayName     = State(initialValue: prefill.displayName)
        _serverKey       = State(initialValue: prefill.serverKey)
        _serverKeyEdited = State(initialValue: true)
        _transportType   = State(initialValue: prefill.transportType)
        _command         = State(initialValue: prefill.command)
        _args            = State(initialValue: prefill.args)
        _url             = State(initialValue: prefill.url)
        _envVars         = State(initialValue: prefill.envVars)
        _notes           = State(initialValue: prefill.notes)
    }

    private var isEditMode: Bool { existing != nil }
    private var title: String { isEditMode ? "Edit Server" : "Add Server" }
    private var isHTTP: Bool { transportType == .http || transportType == .sse }
    private var envLabel: String { isHTTP ? "Request Headers" : "Environment Variables" }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Server Identity") {
                    TextField("Display Name", text: $displayName)
                        .onChange(of: displayName) { newValue in
                            if !serverKeyEdited {
                                serverKey = MCPServerConfig.generateKey(from: newValue)
                            }
                        }

                    HStack {
                        TextField("Server Key", text: $serverKey)
                            .onChange(of: serverKey) { _ in serverKeyEdited = true }
                        if !serverKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .opacity(serverKey == MCPServerConfig.generateKey(from: displayName) ? 0 : 1)
                        }
                    }
                    .help("Used as the key in the agent config file. Auto-generated from display name.")

                    Picker("Transport", selection: $transportType) {
                        Text("stdio (command)").tag(TransportType.stdio)
                        Text("HTTP").tag(TransportType.http)
                        Text("SSE").tag(TransportType.sse)
                    }
                    .pickerStyle(.segmented)
                }

                if isHTTP {
                    Section("URL") {
                        TextField("https://…", text: $url)
                    }
                } else {
                    Section("Command") {
                        TextField("Executable (e.g. npx, /usr/bin/tool)", text: $command)
                    }

                    Section("Arguments") {
                        ForEach(args.indices, id: \.self) { i in
                            HStack {
                                Text(args[i])
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(role: .destructive) { args.remove(at: i) } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            TextField("Add argument…", text: $newArg)
                                .onSubmit { addArg() }
                            Button("Add", action: addArg)
                                .disabled(newArg.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Section(envLabel) {
                    ForEach($envVars) { $env in
                        EnvVarRow(envVar: $env, isRevealed: revealedEnvIds.contains(env.id)) {
                            if revealedEnvIds.contains(env.id) {
                                revealedEnvIds.remove(env.id)
                            } else {
                                revealedEnvIds.insert(env.id)
                            }
                        } onDelete: {
                            envVars.removeAll { $0.id == env.id }
                        }
                    }
                    HStack {
                        TextField("Key", text: $newEnvKey)
                        TextField("Value", text: $newEnvValue)
                        Button("Add") { addEnvVar() }
                            .disabled(newEnvKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if !isHTTP {
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                let config = currentStdioConfig()
                                Task {
                                    isTesting = true
                                    testResult = await tester.test(config: config)
                                    isTesting = false
                                }
                            } label: {
                                if isTesting {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Testing…")
                                    }
                                } else {
                                    Label("Test Connection", systemImage: "network")
                                }
                            }
                            .disabled(isTesting || command.trimmingCharacters(in: .whitespaces).isEmpty)

                            if let result = testResult, !isTesting {
                                ConnectionTestResultView(result: result)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let error = validationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaveDisabled)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationTitle(title)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showPropagation) {
            if let saved = savedConfig {
                PropagationView(config: saved)
                    .environmentObject(store)
            }
        }
        .onChange(of: showPropagation) { isShowing in
            if !isShowing { dismiss() }
        }
    }

    private var isSaveDisabled: Bool {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return true }
        if isHTTP { return url.trimmingCharacters(in: .whitespaces).isEmpty }
        return command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func addArg() {
        let trimmed = newArg.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        args.append(trimmed)
        newArg = ""
    }

    private func addEnvVar() {
        let key = newEnvKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        envVars.append(EnvVar(key: key, value: newEnvValue))
        newEnvKey = ""
        newEnvValue = ""
    }

    private func currentStdioConfig() -> MCPServerConfig {
        MCPServerConfig(
            displayName: displayName,
            command: command.trimmingCharacters(in: .whitespaces),
            args: args,
            envVars: envVars
        )
    }

    private func save() {
        validationError = nil
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedKey  = serverKey.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else { validationError = "Display name is required."; return }
        guard !trimmedKey.isEmpty  else { validationError = "Server key is required."; return }

        do {
            if var config = existing {
                config.displayName    = trimmedName
                config.serverKey      = trimmedKey
                config.transportType  = transportType
                config.command        = isHTTP ? "" : command.trimmingCharacters(in: .whitespaces)
                config.args           = isHTTP ? [] : args
                config.url            = isHTTP ? url.trimmingCharacters(in: .whitespaces) : ""
                config.envVars        = envVars
                config.notes          = notes
                try store.update(config)
                savedConfig = config
            } else {
                let config: MCPServerConfig
                if isHTTP {
                    config = MCPServerConfig(
                        displayName: trimmedName, serverKey: trimmedKey,
                        transportType: transportType,
                        url: url.trimmingCharacters(in: .whitespaces),
                        headers: envVars, notes: notes
                    )
                } else {
                    config = MCPServerConfig(
                        displayName: trimmedName, serverKey: trimmedKey,
                        command: command.trimmingCharacters(in: .whitespaces),
                        args: args, envVars: envVars, notes: notes
                    )
                }
                savedConfig = try store.insert(config)
            }
            if let saved = savedConfig, isEditMode,
               let enabledAgents = try? store.findEnabledAgents(for: saved.uuid),
               !enabledAgents.isEmpty {
                showPropagation = true
            } else {
                dismiss()
            }
        } catch {
            validationError = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - ConnectionTestResultView

private struct ConnectionTestResultView: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isSuccess ? .green : .red)
            Text(result.shortLabel)
                .foregroundColor(result.isSuccess ? .primary : .red)
        }
        .font(.caption)
    }
}

// MARK: - EnvVarRow

private struct EnvVarRow: View {
    @Binding var envVar: EnvVar
    let isRevealed: Bool
    let onToggleReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if envVar.isHint {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Suggested — verify with package docs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(envVar.key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .fixedSize()
                Divider().frame(height: 16)
                if envVar.isSensitive && !isRevealed {
                    SecureField("value", text: $envVar.value)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                } else {
                    TextField("value", text: $envVar.value)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                }
                if envVar.isSensitive {
                    Button(action: onToggleReveal) {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isRevealed ? "Hide value" : "Reveal value")
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddEditConfigView()
            .environmentObject(try! ConfigStore())
    }
}
