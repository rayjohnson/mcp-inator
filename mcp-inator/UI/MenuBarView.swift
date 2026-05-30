import SwiftUI
import AppKit

// Root popover content. Uses a tab view: Servers (config library), Agents, and Catalog.
struct MenuBarView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var registryStore: RegistryStore
    @Environment(\.openAboutWindow) private var openAboutWindow: @Sendable () -> Void
    @Environment(\.openPreferencesWindow) private var openPreferencesWindow: @Sendable () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                NavigationStack {
                    ConfigLibraryView()
                }
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

                NavigationStack {
                    AgentsView()
                }
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }

                NavigationStack {
                    CatalogView()
                }
                .environmentObject(registryStore)
                .environmentObject(store)
                .tabItem {
                    Label("Catalog", systemImage: "square.grid.2x2")
                }
            }
            .frame(width: 420, height: 548)

            Divider()

            HStack {
                Button("About mcp-inator…") {
                    openAboutWindow()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Preferences…") {
                    openPreferencesWindow()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 420)
        .onAppear {
            try? store.refreshAvailability(adapters: allAdapters)
        }
    }

    private var allAdapters: [any AgentAdapter] {
        [ClaudeCodeAdapter(), ClaudeDesktopAdapter(), GeminiCLIAdapter(), CodexCLIAdapter(), GeminiDesktopAdapter()]
    }
}

#Preview {
    MenuBarView()
        // swiftlint:disable:next force_try
        .environmentObject(try! ConfigStore())
        .environmentObject(RegistryStore())
}
