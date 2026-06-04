import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("mcp-inator")
                            .font(.title.bold())
                        Text("MCP server configs for every AI agent, managed in one place.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                HelpSection(title: "What is mcp-inator?", icon: "app.badge") {
                    Text("""
                    mcp-inator is a macOS menu bar app that manages your MCP (Model Context Protocol) \
                    server configurations so you don't have to set them up separately in each AI tool.

                    You configure a server once — give it a name, a command, and any environment \
                    variables it needs — and mcp-inator writes that configuration to every AI agent \
                    you use: Claude, Gemini, Cursor, Zed, and more. When you add a new agent, your \
                    existing servers are already there waiting.

                    By default, mcp-inator lives in your menu bar with no dock icon. You can switch \
                    to dock mode in Preferences if you prefer a traditional window.
                    """)
                }

                Divider()

                HelpSection(title: "Adding and Configuring Servers", icon: "plus.circle") {
                    Text("To add a new MCP server:").bold()
                    VStack(alignment: .leading, spacing: 6) {
                        StepRow(number: "1", text: "Click the mcp-inator icon in your menu bar to open the server list.")
                        StepRow(number: "2", text: "Tap the + button to open the Add Server form.")
                        StepRow(number: "3", text: "Enter the server's name, command, and any arguments or environment variables it needs.")
                        StepRow(number: "4", text: "Hit Save — mcp-inator writes the config to every agent you've enabled.")
                    }
                    .padding(.top, 4)

                    Text(
                        "To enable or disable a server for a specific agent, open the server and toggle the checkbox" +
                        " next to the agent's name. The server config is preserved — it just won't appear in that" +
                        " agent's config file until you re-enable it."
                    )
                    .padding(.top, 8)

                    Text(
                        "Tip: Use the **Private server** toggle to exclude a server from usage reports." +
                        " Private servers are never included in any data sharing."
                    )
                        .padding(.top, 4)
                }

                Divider()

                HelpSection(title: "The Catalog", icon: "square.grid.2x2") {
                    Text("""
                    The Catalog tab shows a curated list of popular MCP servers with pre-filled \
                    defaults so you don't have to hunt down the right command or arguments.
                    """)

                    Text("To install a server from the catalog:").bold().padding(.top, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        StepRow(number: "1", text: "Open the Catalog tab and browse or search for the server you want.")
                        StepRow(number: "2", text: "Tap the entry to see its description, required environment variables, and usage stats.")
                        StepRow(number: "3", text: "Tap Add to Library — the server is added to your list with sane defaults already filled in.")
                        StepRow(number: "4", text: "Fill in any required environment variables (like API keys) and save.")
                    }
                    .padding(.top, 4)

                    Text("The catalog is fetched from GitHub and cached locally, so it works offline once it's been loaded.")
                        .padding(.top, 8)
                }

                Divider()

                HelpSection(title: "Usage Sharing", icon: "chart.bar") {
                    Text("""
                    mcp-inator can optionally share anonymous data about which MCP servers you use. \
                    This helps surface popular servers in the catalog so other users can discover them.
                    """)

                    Group {
                        Text("What **is** shared:").bold().padding(.top, 8)
                        BulletRow(text: "Server key names (e.g. \"filesystem\", \"github-mcp\")")
                        BulletRow(text: "Command basename (e.g. \"npx\", not the full path)")
                        BulletRow(text: "Argument structure — filesystem paths are replaced with <path>")
                        BulletRow(text: "Environment variable key names only — never their values")
                    }

                    Group {
                        Text("What is **never** shared:").bold().padding(.top, 8)
                        BulletRow(text: "Environment variable values (API keys, tokens, passwords)")
                        BulletRow(text: "Full command paths")
                        BulletRow(text: "Private servers (marked with the Private toggle)")
                        BulletRow(text: "Servers you excluded on the review screen")
                        BulletRow(text: "Any personally identifiable information")
                    }

                    Text("""
                    You'll be prompted to opt in after 7 days of use. You can review exactly what \
                    would be sent before submitting. To withdraw at any time, open \
                    Preferences → Contributing Usage Data and tap Withdraw.
                    """)
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - Helpers

private struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpView()
}
