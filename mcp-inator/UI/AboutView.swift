import SwiftUI
import Sparkle

struct AboutView: View {
    let updater: SPUUpdater

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("AboutBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 380, height: 260)
                .clipped()

            VStack(spacing: 6) {
                Text("mcp-inator")
                    .font(.title2.bold())
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 2)

                Text("© 2026 Ray Johnson. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    // swiftlint:disable force_unwrapping
                    Link("GitHub", destination: URL(string: "https://github.com/rayjohnson/mcp-inator")!)
                    Link("Report Issue", destination: URL(string: "https://github.com/rayjohnson/mcp-inator/issues")!)
                    // swiftlint:enable force_unwrapping
                }
                .font(.caption)

                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(width: 380, height: 260)
        .ignoresSafeArea()
    }
}
