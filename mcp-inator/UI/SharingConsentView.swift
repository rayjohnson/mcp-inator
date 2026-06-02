import SwiftUI

struct SharingConsentView: View {
    let servers: [MCPServerConfig]
    let onDismiss: () -> Void

    @State private var showingReview = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Help improve mcp-inator")
                .font(.title2)
                .fontWeight(.semibold)

            Text("""
                You can anonymously share which MCP servers you use. \
                This helps surface popular servers in the catalog. \
                No personal information, file paths, or env var values are ever sent.
                """)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Button("Not Now") {
                    SharingPreferences.shownThisSession = true
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Review What I'd Share") {
                    showingReview = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(28)
        .frame(width: 400)
        .sheet(isPresented: $showingReview) {
            SharingReviewView(
                servers: servers,
                onDismiss: {
                    showingReview = false
                    onDismiss()
                }
            )
        }
    }
}
