import SwiftUI
import Sentry

// swiftlint:disable:next type_body_length
struct AddEditConfigView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var catalogStore: CatalogStore
    @Environment(\.dismiss) private var dismiss

    let existing: MCPServerConfig?
    var onDelete: (() -> Void)?

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
    @State private var isPrivate: Bool
    @State private var revealedEnvIds: Set<UUID> = []
    @State private var validationError: String?
    @State private var confirmingDelete = false
    // Propagation state (shown inline after save, no sheet)
    @State private var propagationAgents: [AgentRecord] = []
    @State private var propagationConfig: MCPServerConfig?
    @State private var propagationPushed = false
    @State private var propagationError: String?
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var showSuggest = false
    private let tester = ConnectionTester()

    init(existing: MCPServerConfig? = nil, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onDelete = onDelete
        _displayName     = State(initialValue: existing?.displayName ?? "")
        _serverKey       = State(initialValue: existing?.serverKey ?? "")
        _serverKeyEdited = State(initialValue: existing != nil)
        _transportType   = State(initialValue: existing?.transportType ?? .stdio)
        _command         = State(initialValue: existing?.command ?? "")
        _args            = State(initialValue: existing?.args ?? [])
        _url             = State(initialValue: existing?.url ?? "")
        _envVars         = State(initialValue: existing?.envVars ?? [])
        _notes           = State(initialValue: existing?.notes ?? "")
        _isPrivate       = State(initialValue: existing?.isPrivate ?? false)
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
        _isPrivate       = State(initialValue: false)
    }

    private var isEditMode: Bool { existing != nil }
    private var title: String { isEditMode ? "Edit Server" : "Add Server" }
    private var isHTTP: Bool { transportType == .http || transportType == .sse }
    private var envLabel: String { isHTTP ? "Request Headers" : "Environment Variables" }

    var body: some View {
        VStack(spacing: 0) {
            if !propagationAgents.isEmpty || propagationPushed {
                propagationBody
            } else {
                editFormBody
            }
        }
        .navigationTitle((!propagationAgents.isEmpty || propagationPushed) ? "Push Changes" : title)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showSuggest) {
            if let config = existing {
                SuggestServerView(config: config)
            }
        }
        .confirmationDialog(
            "Delete \"\(existing?.displayName ?? "")\"?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteServer() }
            Button("Cancel", role: .cancel) { confirmingDelete = false }
        } message: {
            Text("This removes the server from your library and disables it for all agents.")
        }
    }

    // MARK: - Edit Form

    private var editFormBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: Server Identity
                    formSection("Server Identity") {
                        fieldLabel("Display Name")
                        TextField("My MCP Server", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: displayName) { newValue in
                                if !serverKeyEdited {
                                    serverKey = MCPServerConfig.generateKey(from: newValue)
                                }
                            }

                        fieldLabel("Server Key")
                        HStack {
                            TextField("my-server", text: $serverKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: serverKey) { newValue in
                                    let generated = MCPServerConfig.generateKey(from: displayName)
                                    serverKeyEdited = !newValue.isEmpty && newValue != generated
                                }
                                .help("Used as the key in the agent config file. Auto-generated from display name.")
                            if serverKeyConflict {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .help("This key is already used by another server.")
                            }
                        }

                        fieldLabel("Transport")
                        Picker("", selection: $transportType) {
                            Text("stdio (command)").tag(TransportType.stdio)
                            Text("HTTP").tag(TransportType.http)
                            Text("SSE").tag(TransportType.sse)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // MARK: Command or URL
                    if isHTTP {
                        formSection("URL") {
                            TextField("https://…", text: $url)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        formSection("Command") {
                            TextField("npx, uvx, or /path/to/tool", text: $command)
                                .textFieldStyle(.roundedBorder)
                        }

                        formSection("Arguments") {
                            ForEach(args.indices, id: \.self) { i in
                                HStack {
                                    Text(args[i])
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button(role: .destructive) { args.remove(at: i) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            HStack {
                                TextField("Add argument…", text: $newArg)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { addArg() }
                                Button("Add", action: addArg)
                                    .disabled(newArg.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // MARK: Env vars / Headers
                    formSection(envLabel) {
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
                                .textFieldStyle(.roundedBorder)
                            TextField("Value", text: $newEnvValue)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") { addEnvVar() }
                                .disabled(newEnvKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    // MARK: Notes
                    formSection("Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                        Toggle("Private server", isOn: $isPrivate)
                            .help("Private servers are never included in anonymous usage reports.")
                    }

                    // MARK: Test Connection
                    HStack(spacing: 12) {
                        Button {
                            let config = currentConfig()
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
                        .disabled(isTesting || testButtonDisabled)

                        if let result = testResult, !isTesting {
                            ConnectionTestResultView(result: result)
                        }
                    }

                    // MARK: Suggest / Delete (edit mode only)
                    if isEditMode, let config = existing,
                       !isPrivate,
                       !catalogStore.viewModels.contains(where: { $0.entry.serverKey == config.serverKey }) {
                        Divider()
                            .padding(.top, 4)
                        Button {
                            showSuggest = true
                        } label: {
                            Label("Suggest to Catalog", systemImage: "plus.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if isEditMode {
                        Divider()
                            .padding(.top, 4)
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete Server", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
            }
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
    }

    // MARK: - Inline Propagation

    private var propagationBody: some View {
        VStack(spacing: 0) {
            if propagationPushed {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("Changes pushed.")
                        .font(.headline)
                    Text("Restart each affected agent to apply them.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let cfg = propagationConfig {
                        Text("\"\(cfg.displayName)\" is enabled for these agents. Push the updated config now?")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    List(propagationAgents) { agent in
                        HStack(spacing: 8) {
                            AgentIcon(agentType: agent.agentType)
                                .frame(width: 20, height: 20)
                            Text(agent.displayName)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 80)
                }
            }

            if let err = propagationError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()
            HStack {
                if propagationPushed {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                    Spacer()
                } else {
                    Button("Skip") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    Button("Push to All") { doPushAll() }
                        .buttonStyle(.borderedProminent)
                        .disabled(propagationAgents.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Section helpers

    @ViewBuilder
    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            content()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Computed properties

    private var serverKeyConflict: Bool {
        let key = serverKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return false }
        return store.configs.contains { cfg in
            cfg.serverKey == key && cfg.id != existing?.id
        }
    }

    private var isDirty: Bool {
        guard let existing = existing else { return true }
        return displayName.trimmingCharacters(in: .whitespaces) != existing.displayName
            || serverKey.trimmingCharacters(in: .whitespaces) != existing.serverKey
            || transportType != existing.transportType
            || command.trimmingCharacters(in: .whitespaces) != existing.command
            || args != existing.args
            || url.trimmingCharacters(in: .whitespaces) != existing.url
            || envVars != existing.envVars
            || notes != existing.notes
            || isPrivate != existing.isPrivate
    }

    private var isSaveDisabled: Bool {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return true }
        if serverKeyConflict { return true }
        if isHTTP && url.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if !isHTTP && command.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return !isDirty
    }

    // MARK: - Actions

    private func breadcrumb(_ message: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: "ui")
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    private func deleteServer() {
        guard let config = existing else { return }
        breadcrumb("delete: removing server '\(config.serverKey)'")
        do {
            try store.delete(config)
            if let onDelete { onDelete() } else { dismiss() }
        } catch {
            breadcrumb("delete: failed — \(error.localizedDescription)", level: .error)
            validationError = "Delete failed: \(error.localizedDescription)"
        }
    }

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

    private var testButtonDisabled: Bool {
        if isHTTP { return url.trimmingCharacters(in: .whitespaces).isEmpty }
        return command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func currentConfig() -> MCPServerConfig {
        if isHTTP {
            return MCPServerConfig(
                displayName: displayName,
                serverKey: serverKey,
                transportType: transportType,
                url: url.trimmingCharacters(in: .whitespaces),
                headers: envVars
            )
        }
        return MCPServerConfig(
            displayName: displayName,
            command: command.trimmingCharacters(in: .whitespaces),
            args: args,
            envVars: envVars
        )
    }

    private func makeNewConfig(name: String, key: String) -> MCPServerConfig {
        if isHTTP {
            return MCPServerConfig(
                displayName: name, serverKey: key,
                transportType: transportType,
                url: url.trimmingCharacters(in: .whitespaces),
                headers: envVars, notes: notes, isPrivate: isPrivate
            )
        }
        return MCPServerConfig(
            displayName: name, serverKey: key,
            command: command.trimmingCharacters(in: .whitespaces),
            args: args, envVars: envVars, notes: notes, isPrivate: isPrivate
        )
    }

    private func save() {
        validationError = nil
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedKey  = serverKey.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            validationError = "Display name is required."
            breadcrumb("save: validation failed — display name empty", level: .warning)
            return
        }
        guard !trimmedKey.isEmpty else {
            validationError = "Server key is required."
            breadcrumb("save: validation failed — server key empty", level: .warning)
            return
        }

        do {
            let saved: MCPServerConfig
            if var config = existing {
                breadcrumb("save: updating server '\(trimmedKey)'")
                config.displayName    = trimmedName
                config.serverKey      = trimmedKey
                config.transportType  = transportType
                config.command        = isHTTP ? "" : command.trimmingCharacters(in: .whitespaces)
                config.args           = isHTTP ? [] : args
                config.url            = isHTTP ? url.trimmingCharacters(in: .whitespaces) : ""
                config.envVars        = envVars
                config.notes          = notes
                config.isPrivate      = isPrivate
                try store.update(config)
                saved = config
            } else {
                breadcrumb("save: inserting new server '\(trimmedKey)'")
                saved = try store.insert(makeNewConfig(name: trimmedName, key: trimmedKey))
            }
            let visibleIds = Set(store.visibleAgents.compactMap(\.id))
            let enabledVisible = isEditMode
                ? ((try? store.findEnabledAgents(for: saved.uuid)) ?? [])
                    .filter { visibleIds.contains($0.id ?? -1) }
                : []
            if !enabledVisible.isEmpty {
                breadcrumb("save: showing propagation panel for '\(trimmedKey)'")
                propagationConfig = saved
                propagationAgents = enabledVisible
            } else {
                breadcrumb("save: dismissing after save '\(trimmedKey)'")
                dismiss()
            }
        } catch {
            breadcrumb("save: failed — \(error.localizedDescription)", level: .error)
            validationError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func doPushAll() {
        guard let cfg = propagationConfig else { return }
        for agent in propagationAgents {
            guard let agentId = agent.id,
                  let adapter = AdapterRegistry.adapter(for: agent.agentType) else { continue }
            let path = URL(fileURLWithPath: agent.configPath)
            do {
                _ = try store.enableConfig(uuid: cfg.uuid, agentId: agentId,
                                           adapter: adapter, configPath: path)
            } catch {
                propagationError = "Failed to push to \(agent.displayName): \(error.localizedDescription)"
                return
            }
        }
        propagationPushed = true
    }
}

// MARK: - ConnectionTestResultView

private struct ConnectionTestResultView: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundColor(tintColor)
            Text(result.shortLabel)
                .foregroundColor(result.isSuccess ? .primary : tintColor)
        }
        .font(.caption)
    }

    private var iconName: String {
        if result.isSuccess { return "checkmark.circle.fill" }
        if result.isWarning { return "lock.circle.fill" }
        return "xmark.circle.fill"
    }

    private var tintColor: Color {
        if result.isSuccess { return .green }
        if result.isWarning { return .orange }
        return .red
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
            // swiftlint:disable:next force_try
            .environmentObject(try! ConfigStore())
    }
}
