import SwiftUI
import ServiceManagement

// MARK: - LaunchAtLoginManaging Protocol

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

// MARK: - SMAppServiceAdapter

struct SMAppServiceAdapter: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @EnvironmentObject private var appModeManager: AppModeManager
    private var launchAtLogin: any LaunchAtLoginManaging

    @State private var launchAtLoginError: String?

    init(launchAtLogin: (any LaunchAtLoginManaging)? = nil) {
        self.launchAtLogin = launchAtLogin ?? SMAppServiceAdapter()
    }

    @AppStorage("sharingConsented") private var sharingConsented = false
    @State private var privateCatalogURLs: [String] = []
    @State private var newCatalogURL: String = ""

    var body: some View {
        Form {
            Section("Contributing Usage Data") {
                Text(
                    "mcp-inator can share anonymous data about which MCP servers you use, helping surface popular" +
                    " servers in the catalog. Only server names and command structure are shared — never API keys," +
                    " passwords, or personal information. Private servers are always excluded."
                )
                .foregroundColor(.secondary)
                    .font(.callout)
                if sharingConsented {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("You are contributing anonymous usage data.")
                        Spacer()
                        Button("Withdraw") {
                            sharingConsented = false
                            UsageSharingService.shared.clearPending()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("General") {
                Picker("App Mode", selection: Binding(
                    get: { appModeManager.showInDock },
                    set: { appModeManager.setShowInDock($0) }
                )) {
                    Text("Menu Bar").tag(false)
                    Text("Dock").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(appModeManager.isTransitioning)

                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                if let errorMsg = launchAtLoginError {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Private Catalogs") {
                Text("Add a URL to a private catalog JSON file. Each source gets its own tab in the Catalog view.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                ForEach(privateCatalogURLs, id: \.self) { url in
                    HStack {
                        Text(url)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            privateCatalogURLs.removeAll { $0 == url }
                            PrivateCatalogPreferences.urls = privateCatalogURLs
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("https://example.com/catalog.json", text: $newCatalogURL)
                    Button("Add") {
                        let trimmed = newCatalogURL.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
                        guard !privateCatalogURLs.contains(trimmed) else { return }
                        privateCatalogURLs.append(trimmed)
                        PrivateCatalogPreferences.urls = privateCatalogURLs
                        newCatalogURL = ""
                    }
                    .disabled(
                        newCatalogURL.trimmingCharacters(in: .whitespaces).isEmpty ||
                        URL(string: newCatalogURL.trimmingCharacters(in: .whitespaces)) == nil
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
        .onAppear {
            privateCatalogURLs = PrivateCatalogPreferences.urls
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
