import Foundation

struct ImportSourceScanner {
    let adapters: [any AgentAdapter]
    let fileExists: (URL) -> Bool

    init(
        adapters: [any AgentAdapter] = AdapterRegistry.all,
        fileExists: @escaping (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        }
    ) {
        self.adapters = adapters
        self.fileExists = fileExists
    }

    func scan() -> [ImportSource] {
        adapters.compactMap { adapter in
            guard adapter.isInstalled() else { return nil }
            if adapter.isAppManaged {
                return ImportSource(
                    displayName: adapter.displayName,
                    agentType: adapter.agentType,
                    adapter: adapter,
                    configPath: adapter.defaultConfigPath(),
                    isImportable: false,
                    unavailableReason: "MCP servers are managed inside the \(adapter.displayName) app"
                )
            }
            let path = adapter.defaultConfigPath()
            guard fileExists(path) else { return nil }
            return ImportSource(
                displayName: adapter.displayName,
                agentType: adapter.agentType,
                adapter: adapter,
                configPath: path,
                isImportable: true,
                unavailableReason: nil
            )
        }
    }
}
