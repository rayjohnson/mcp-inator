import Foundation

enum AdapterRegistry {
    nonisolated(unsafe) static let all: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        ClaudeDesktopAdapter(),
        GeminiCLIAdapter(),
        CodexCLIAdapter(),
        GeminiDesktopAdapter(),
        CursorAdapter()
    ]

    static func adapter(for agentType: AgentType) -> (any AgentAdapter)? {
        all.first { $0.agentType == agentType }
    }
}
