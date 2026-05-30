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

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
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
