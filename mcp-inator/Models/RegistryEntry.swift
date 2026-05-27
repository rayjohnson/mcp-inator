import Foundation

// MARK: - PackageType

enum PackageType: String, Codable, Sendable {
    case npm
    case pypi
    case oci
}

// MARK: - RemoteTransportType

enum RemoteTransportType: String, Codable, Sendable {
    case streamableHTTP = "streamable-http"
    case sse
}

// MARK: - RegistryEnvVar

struct RegistryEnvVar: Equatable, Codable, Sendable {
    var name: String
    var description: String
    var isRequired: Bool
    var isSecret: Bool
    var valueTemplate: String?
}

// MARK: - RegistryEntry

struct RegistryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var displayName: String
    var description: String
    var packageType: PackageType?
    var packageIdentifier: String?
    var remoteURL: String?
    var remoteType: RemoteTransportType?
    var remoteHeaders: [RegistryEnvVar]
    var envVars: [RegistryEnvVar]
    var repositoryURL: String?
    var version: String

    // MARK: Computed

    var derivedCommand: String? {
        guard let pt = packageType, let identifier = packageIdentifier else { return nil }
        return RegistryEntry.deriveCommand(packageType: pt, identifier: identifier).command
    }

    var derivedArgs: [String]? {
        guard let pt = packageType, let identifier = packageIdentifier else { return nil }
        return RegistryEntry.deriveCommand(packageType: pt, identifier: identifier).args
    }

    var transportType: TransportType {
        if packageType != nil { return .stdio }
        if remoteType == .sse { return .sse }
        return .http
    }

    var isActionable: Bool {
        (packageType != nil && packageIdentifier != nil) || remoteURL != nil
    }

    // MARK: Pure Static Functions

    static func deriveCommand(packageType: PackageType, identifier: String) -> (command: String, args: [String]) {
        switch packageType {
        case .npm:  return ("npx", ["-y", identifier])
        case .pypi: return ("uvx", [identifier])
        case .oci:  return ("docker", ["run", identifier])
        }
    }

    static func displayName(from registryName: String) -> String {
        let component = registryName.split(separator: "/").last.map(String.init) ?? registryName

        var name = component
        let suffixes = ["-mcp-servers", "-mcp-server", "-mcp"]
        for suffix in suffixes {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }

        name = name.replacingOccurrences(of: "-", with: " ")
        name = name.replacingOccurrences(of: "_", with: " ")

        return name.split(separator: " ")
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

// MARK: - Failable init from raw API

extension RegistryEntry {
    init?(raw wrapper: RegistryAPIServerWrapper) {
        let server = wrapper.server
        self.id = server.name
        self.displayName = RegistryEntry.displayName(from: server.name)
        self.description = server.description
        self.version = server.version
        self.repositoryURL = server.repository.flatMap { $0.url }

        // stdio package takes precedence over remotes
        let pkg = server.packages?.first { PackageType(rawValue: $0.registryType) != nil }

        if let pkg, let pkgType = PackageType(rawValue: pkg.registryType) {
            self.packageType = pkgType
            self.packageIdentifier = pkg.identifier
            self.envVars = (pkg.environmentVariables ?? []).compactMap { apiVar in
                guard !apiVar.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return RegistryEnvVar(
                    name: apiVar.name,
                    description: apiVar.description ?? "",
                    isRequired: apiVar.isRequired ?? false,
                    isSecret: apiVar.isSecret ?? false,
                    valueTemplate: nil
                )
            }
            self.remoteURL = nil
            self.remoteType = nil
            self.remoteHeaders = []
        } else if let remote = server.remotes?.first {
            self.packageType = nil
            self.packageIdentifier = nil
            self.envVars = []
            self.remoteURL = remote.url
            self.remoteType = RemoteTransportType(rawValue: remote.type)
            self.remoteHeaders = (remote.headers ?? []).compactMap { apiHeader in
                guard !apiHeader.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return RegistryEnvVar(
                    name: apiHeader.name,
                    description: apiHeader.description ?? "",
                    isRequired: apiHeader.isRequired ?? false,
                    isSecret: apiHeader.isSecret ?? false,
                    valueTemplate: apiHeader.value
                )
            }
        } else {
            return nil
        }
    }
}
