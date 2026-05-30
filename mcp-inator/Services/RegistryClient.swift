import Foundation

// MARK: - Raw API Decode Types (internal to this file boundary)

struct RegistryAPIResponse: Decodable {
    let servers: [RegistryAPIServerWrapper]
    let metadata: RegistryAPIMetadata
}

struct RegistryAPIServerWrapper: Decodable {
    let server: RegistryAPIServer
    let meta: RegistryAPIMeta

    enum CodingKeys: String, CodingKey {
        case server
        case meta = "_meta"
    }
}

struct RegistryAPIServer: Decodable {
    let name: String
    let description: String
    let version: String
    let packages: [RegistryAPIPackage]?
    let remotes: [RegistryAPIRemote]?
    let repository: RegistryAPIRepository?
}

struct RegistryAPIPackage: Decodable {
    let registryType: String
    let identifier: String
    let version: String?
    let environmentVariables: [RegistryAPIEnvVar]?
    let transport: RegistryAPITransport?
}

struct RegistryAPITransport: Decodable {
    let type: String
}

struct RegistryAPIRemote: Decodable {
    let type: String
    let url: String
    let headers: [RegistryAPIEnvVar]?
}

struct RegistryAPIEnvVar: Decodable {
    let name: String
    let description: String?
    let isRequired: Bool?
    let isSecret: Bool?
    let format: String?
    let value: String?
}

struct RegistryAPIMeta: Decodable {
    let official: RegistryAPIOfficialMeta

    enum CodingKeys: String, CodingKey {
        case official = "io.modelcontextprotocol.registry/official"
    }
}

struct RegistryAPIOfficialMeta: Decodable {
    let isLatest: Bool
    let status: String
}

struct RegistryAPIMetadata: Decodable {
    let count: Int
    let nextCursor: String?
}

struct RegistryAPIRepository: Decodable {
    let url: String?
    let source: String?
}

// MARK: - Pure Transformation Functions

func filterLatest(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper] {
    wrappers.filter { $0.meta.official.isLatest }
}

func deduplicate(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper] {
    var seen = Set<String>()
    return wrappers.filter { seen.insert($0.server.name).inserted }
}

// MARK: - RegistryClient Protocol

protocol RegistryClient: Sendable {
    func search(query: String, pageSize: Int) async throws -> [RegistryEntry]
}

// MARK: - URLSessionRegistryClient

struct URLSessionRegistryClient: RegistryClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, pageSize: Int = 100) async throws -> [RegistryEntry] {
        // swiftlint:disable:next force_unwrapping
        var components = URLComponents(string: "https://registry.modelcontextprotocol.io/v0/servers")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(RegistryAPIResponse.self, from: data)

        let filtered = filterLatest(response.servers)
        let deduped = deduplicate(filtered)
        return deduped.compactMap { RegistryEntry(raw: $0) }
    }
}
