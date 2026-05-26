import Foundation

if CommandLine.arguments.contains("--mcp-server") {
    MCPServerRunner.start()
} else {
    mcp_inatorApp.main()
}
