import SwiftUI
import AppKit

// Root popover content. Uses a tab view: Servers (config library), Agents, and Catalog.
struct MenuBarView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var registryStore: RegistryStore
    @Environment(\.openAboutWindow) private var openAboutWindow: @Sendable () -> Void
    @Environment(\.openPreferencesWindow) private var openPreferencesWindow: @Sendable () -> Void
    @Environment(\.openHelpWindow) private var openHelpWindow: @Sendable () -> Void
    @State private var showManageAgents = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                NavigationStack {
                    ConfigLibraryView(selectedConfig: .constant(nil), isCompact: true)
                }
                .environment(\.navigationIsCompact, true)
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }

                NavigationStack {
                    AgentsView(
                        showManageAgents: $showManageAgents,
                        selectedAgent: .constant(nil),
                        isCompact: true
                    )
                }
                .environment(\.navigationIsCompact, true)
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }

                NavigationStack {
                    CatalogView(selectedEntry: .constant(nil), isCompact: true)
                }
                .environmentObject(registryStore)
                .environmentObject(store)
                .environment(\.navigationIsCompact, true)
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

                Button("Help…") {
                    openHelpWindow()
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
        AdapterRegistry.all
    }
}

#Preview {
    MenuBarView()
        // swiftlint:disable:next force_try
        .environmentObject(try! ConfigStore())
        .environmentObject(RegistryStore())
}
