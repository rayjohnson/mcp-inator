import SwiftUI
import AppKit

// Displays a recognizable icon for each agent type.
// Anthropic agents: loads Claude.app icon from NSWorkspace.
// CLI-only agents (Gemini, Codex): renders a styled letter badge.
struct AgentIcon: View {
    let agentType: AgentType

    var body: some View {
        switch agentType {
        case .claudeCode, .claudeDesktop:
            ClaudeAppIcon()
        case .geminiCLI:
            LetterBadge(letter: "G", background: Color(red: 0.26, green: 0.52, blue: 0.96))
        case .codexCLI:
            LetterBadge(letter: "X", background: Color(red: 0.07, green: 0.07, blue: 0.07))
        case .geminiDesktop:
            GeminiDesktopAppIcon()
        }
    }
}

// MARK: - ClaudeAppIcon

private struct ClaudeAppIcon: View {
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                LetterBadge(letter: "A", background: Color(red: 0.85, green: 0.45, blue: 0.25))
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        guard appIcon == nil else { return }
        let bundleIDs = ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        for bid in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
                return
            }
        }
    }
}

// MARK: - GeminiDesktopAppIcon

private struct GeminiDesktopAppIcon: View {
    @State private var appIcon: NSImage?

    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                LetterBadge(letter: "G", background: Color(red: 0.11, green: 0.53, blue: 0.96))
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        guard appIcon == nil else { return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
            return
        }
        let appPath = "/Applications/Gemini.app"
        if FileManager.default.fileExists(atPath: appPath) {
            appIcon = NSWorkspace.shared.icon(forFile: appPath)
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
        ForEach(AgentType.allCases, id: \.self) { type in
            AgentIcon(agentType: type)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
    .padding()
}
