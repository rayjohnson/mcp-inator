import Foundation

struct ImportSource {
    let displayName: String
    let agentType: AgentType
    let adapter: any AgentAdapter
    let configPath: URL
    let isImportable: Bool
    let unavailableReason: String?
}
