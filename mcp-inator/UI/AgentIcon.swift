import SwiftUI
import AppKit

// Data-driven agent icon. Icon config comes from AdapterRegistry — adding a new
// agent with a custom icon requires only updating its AgentDefinition.
struct AgentIcon: View {
    let agentType: AgentType

    var body: some View {
        if let config = AdapterRegistry.definition(for: agentType)?.icon {
            AppIconView(config: config)
        } else {
            LetterBadge(letter: "?", background: .secondary)
        }
    }
}

// MARK: - AppIconView

private struct AppIconView: View {
    let config: AgentIconConfig
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                LetterBadge(
                    letter: config.fallback.letter,
                    background: Color(
                        red: config.fallback.red,
                        green: config.fallback.green,
                        blue: config.fallback.blue
                    )
                )
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        guard appIcon == nil else { return }
        for bid in config.bundleIds {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
                return
            }
        }
        for path in config.appPaths where FileManager.default.fileExists(atPath: path) {
            appIcon = NSWorkspace.shared.icon(forFile: path)
            return
        }
    }
}

// MARK: - LetterBadge

private struct LetterBadge: View {
    let letter: String
    let background: Color

    var body: some View {
        ZStack {
            background
            Text(letter)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        ForEach(AdapterRegistry.all, id: \.agentType.rawValue) { adapter in
            AgentIcon(agentType: adapter.agentType)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
    .padding()
}
