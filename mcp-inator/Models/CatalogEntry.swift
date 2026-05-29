import Foundation

// MARK: - CatalogCategory

enum CatalogCategory: String, Codable, CaseIterable, Identifiable {
    case codeAndDevelopment = "Code & Development"
    case productivity       = "Productivity"
    case dataAndAnalytics   = "Data & Analytics"
    case communication      = "Communication"
    case infrastructure     = "Infrastructure"
    case aiAndLLMs          = "AI & LLMs"
    case webAndBrowser      = "Web & Browser"

    var id: String { rawValue }
}

// MARK: - CatalogFile (servers.json top-level)

struct CatalogFile: Decodable, Sendable {
    let metadata: CatalogFileMetadata
    let entries: [CatalogEntry]
}

struct CatalogFileMetadata: Decodable, Sendable {
    let schemaVersion: String
    let bundledAt: String?
    let entryCount: Int?
}

// MARK: - CatalogEntry

struct CatalogEntry: Identifiable, Codable, Sendable {
    var id: String
    var displayName: String
    var category: CatalogCategory
    var shortDescription: String
    var curatorNote: String?
    var transportType: String
    var command: String
    var args: [String]
    var url: String?
    var envVars: [EnvVarDefinition]
    var requiredArgs: [RequiredArgDefinition]?
    var documentationURL: String?
    var repositoryURL: String?
    var isVerified: Bool
    var isFirstParty: Bool
    var alternativeTo: String?
    var serverKey: String

    enum CodingKeys: String, CodingKey {
        case id, displayName, category, shortDescription, curatorNote
        case transportType, command, args, url, envVars, requiredArgs
        case documentationURL, repositoryURL, isVerified, isFirstParty
        case alternativeTo, serverKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        displayName     = try c.decode(String.self, forKey: .displayName)
        category        = try c.decode(CatalogCategory.self, forKey: .category)
        shortDescription = try c.decode(String.self, forKey: .shortDescription)
        curatorNote     = try c.decodeIfPresent(String.self, forKey: .curatorNote)
        transportType   = try c.decode(String.self, forKey: .transportType)
        command         = try c.decode(String.self, forKey: .command)
        args            = try c.decode([String].self, forKey: .args)
        url             = try c.decodeIfPresent(String.self, forKey: .url)
        envVars         = try c.decode([EnvVarDefinition].self, forKey: .envVars)
        requiredArgs    = try c.decodeIfPresent([RequiredArgDefinition].self, forKey: .requiredArgs)
        documentationURL = try c.decodeIfPresent(String.self, forKey: .documentationURL)
        repositoryURL   = try c.decodeIfPresent(String.self, forKey: .repositoryURL)
        isVerified      = (try? c.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        isFirstParty    = (try? c.decodeIfPresent(Bool.self, forKey: .isFirstParty)) ?? false
        alternativeTo   = try c.decodeIfPresent(String.self, forKey: .alternativeTo)
        serverKey       = try c.decode(String.self, forKey: .serverKey)
    }
}

// MARK: - EnvVarDefinition

struct EnvVarDefinition: Codable, Sendable, Identifiable {
    var name: String
    var description: String
    var isRequired: Bool
    var isSensitive: Bool

    var id: String { name }
}

// MARK: - RequiredArgDefinition

struct RequiredArgDefinition: Codable, Sendable, Identifiable {
    var name: String
    var description: String
    var placeholder: String
    var isRequired: Bool

    var id: String { name }
}

// MARK: - StatsFile (stats.json top-level)

struct StatsFile: Decodable, Sendable {
    let metadata: StatsFileMetadata
    let servers: [String: ServerMetrics]
}

struct StatsFileMetadata: Decodable, Sendable {
    let schemaVersion: String
    let computedAt: String
}

// MARK: - ServerMetrics

struct ServerMetrics: Codable, Sendable {
    var serverKey: String
    var repositoryURL: String?
    var starCount: Int?
    var forkCount: Int?
    var lastCommitDate: String?
    var openIssueCount: Int?
    var isArchived: Bool
    var githubFetchedAt: String?
    var isTrending: Bool
    var trendingScore: Int?
    var sentimentSummary: String?
    var mentionCount: Int?
    var periodDays: Int?
    var sentimentComputedAt: String?
    var userCount: Int?
    var enabledCount: Int?
    var weeklyActiveCount: Int?
    var usageAggregatedAt: String?

    enum CodingKeys: String, CodingKey {
        case serverKey, repositoryURL, starCount, forkCount, lastCommitDate
        case openIssueCount, isArchived, githubFetchedAt, isTrending
        case trendingScore, sentimentSummary, mentionCount, periodDays
        case sentimentComputedAt, userCount, enabledCount, weeklyActiveCount
        case usageAggregatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverKey          = try c.decode(String.self, forKey: .serverKey)
        repositoryURL      = try c.decodeIfPresent(String.self, forKey: .repositoryURL)
        starCount          = try c.decodeIfPresent(Int.self, forKey: .starCount)
        forkCount          = try c.decodeIfPresent(Int.self, forKey: .forkCount)
        lastCommitDate     = try c.decodeIfPresent(String.self, forKey: .lastCommitDate)
        openIssueCount     = try c.decodeIfPresent(Int.self, forKey: .openIssueCount)
        isArchived         = (try? c.decodeIfPresent(Bool.self, forKey: .isArchived)) ?? false
        githubFetchedAt    = try c.decodeIfPresent(String.self, forKey: .githubFetchedAt)
        isTrending         = (try? c.decodeIfPresent(Bool.self, forKey: .isTrending)) ?? false
        trendingScore      = try c.decodeIfPresent(Int.self, forKey: .trendingScore)
        sentimentSummary   = try c.decodeIfPresent(String.self, forKey: .sentimentSummary)
        mentionCount       = try c.decodeIfPresent(Int.self, forKey: .mentionCount)
        periodDays         = try c.decodeIfPresent(Int.self, forKey: .periodDays)
        sentimentComputedAt = try c.decodeIfPresent(String.self, forKey: .sentimentComputedAt)
        userCount          = try c.decodeIfPresent(Int.self, forKey: .userCount)
        enabledCount       = try c.decodeIfPresent(Int.self, forKey: .enabledCount)
        weeklyActiveCount  = try c.decodeIfPresent(Int.self, forKey: .weeklyActiveCount)
        usageAggregatedAt  = try c.decodeIfPresent(String.self, forKey: .usageAggregatedAt)
    }
}

// MARK: - CatalogViewModel

struct CatalogViewModel: Identifiable, Sendable {
    let entry: CatalogEntry
    let metrics: ServerMetrics?

    var id: String { entry.id }

    var isTrending: Bool   { metrics?.isTrending ?? false }
    var trendingScore: Int? { metrics?.trendingScore }
    var starCount: Int?    { metrics?.starCount }
    var lastCommitDate: String? { metrics?.lastCommitDate }
    var userCount: Int?    { metrics?.userCount }
    var sentimentSummary: String? { metrics?.sentimentSummary }
    var isAlternative: Bool { entry.alternativeTo != nil }
}

// MARK: - MCPServerConfig convenience init from CatalogEntry

extension MCPServerConfig {
    init(from entry: CatalogEntry) {
        let transport: TransportType = entry.transportType == "http" ? .http : .stdio
        let envVars = entry.envVars.map { v -> EnvVar in
            var ev = EnvVar(key: v.name, value: "", isSensitive: v.isSensitive)
            ev.isHint = true
            return ev
        }
        if transport == .stdio {
            self.init(
                displayName: entry.displayName,
                serverKey: entry.serverKey,
                command: entry.command,
                args: entry.args,
                envVars: envVars
            )
        } else {
            self.init(
                displayName: entry.displayName,
                serverKey: entry.serverKey,
                transportType: transport,
                url: entry.url ?? "",
                headers: envVars
            )
        }
    }
}
