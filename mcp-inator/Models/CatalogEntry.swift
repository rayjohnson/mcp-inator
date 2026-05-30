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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        category = try container.decode(CatalogCategory.self, forKey: .category)
        shortDescription = try container.decode(String.self, forKey: .shortDescription)
        curatorNote = try container.decodeIfPresent(String.self, forKey: .curatorNote)
        transportType = try container.decode(String.self, forKey: .transportType)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decode([String].self, forKey: .args)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        envVars = try container.decode([EnvVarDefinition].self, forKey: .envVars)
        requiredArgs = try container.decodeIfPresent([RequiredArgDefinition].self, forKey: .requiredArgs)
        documentationURL = try container.decodeIfPresent(String.self, forKey: .documentationURL)
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL)
        isVerified = (try? container.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        isFirstParty = (try? container.decodeIfPresent(Bool.self, forKey: .isFirstParty)) ?? false
        alternativeTo = try container.decodeIfPresent(String.self, forKey: .alternativeTo)
        serverKey = try container.decode(String.self, forKey: .serverKey)
    }

    init(
        id: String, displayName: String, category: CatalogCategory,
        shortDescription: String, curatorNote: String? = nil,
        transportType: String = "stdio", command: String = "", args: [String] = [],
        url: String? = nil, envVars: [EnvVarDefinition] = [], requiredArgs: [RequiredArgDefinition]? = nil,
        documentationURL: String? = nil, repositoryURL: String? = nil,
        isVerified: Bool = false, isFirstParty: Bool = false,
        alternativeTo: String? = nil, serverKey: String
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.shortDescription = shortDescription
        self.curatorNote = curatorNote
        self.transportType = transportType
        self.command = command
        self.args = args
        self.url = url
        self.envVars = envVars
        self.requiredArgs = requiredArgs
        self.documentationURL = documentationURL
        self.repositoryURL = repositoryURL
        self.isVerified = isVerified
        self.isFirstParty = isFirstParty
        self.alternativeTo = alternativeTo
        self.serverKey = serverKey
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverKey = try container.decode(String.self, forKey: .serverKey)
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL)
        starCount = try container.decodeIfPresent(Int.self, forKey: .starCount)
        forkCount = try container.decodeIfPresent(Int.self, forKey: .forkCount)
        lastCommitDate = try container.decodeIfPresent(String.self, forKey: .lastCommitDate)
        openIssueCount = try container.decodeIfPresent(Int.self, forKey: .openIssueCount)
        isArchived = (try? container.decodeIfPresent(Bool.self, forKey: .isArchived)) ?? false
        githubFetchedAt = try container.decodeIfPresent(String.self, forKey: .githubFetchedAt)
        isTrending = (try? container.decodeIfPresent(Bool.self, forKey: .isTrending)) ?? false
        trendingScore = try container.decodeIfPresent(Int.self, forKey: .trendingScore)
        sentimentSummary = try container.decodeIfPresent(String.self, forKey: .sentimentSummary)
        mentionCount = try container.decodeIfPresent(Int.self, forKey: .mentionCount)
        periodDays = try container.decodeIfPresent(Int.self, forKey: .periodDays)
        sentimentComputedAt = try container.decodeIfPresent(String.self, forKey: .sentimentComputedAt)
        userCount = try container.decodeIfPresent(Int.self, forKey: .userCount)
        enabledCount = try container.decodeIfPresent(Int.self, forKey: .enabledCount)
        weeklyActiveCount = try container.decodeIfPresent(Int.self, forKey: .weeklyActiveCount)
        usageAggregatedAt = try container.decodeIfPresent(String.self, forKey: .usageAggregatedAt)
    }

    init(
        serverKey: String, repositoryURL: String? = nil,
        starCount: Int? = nil, forkCount: Int? = nil, lastCommitDate: String? = nil,
        openIssueCount: Int? = nil, isArchived: Bool = false, githubFetchedAt: String? = nil,
        isTrending: Bool = false, trendingScore: Int? = nil,
        sentimentSummary: String? = nil, mentionCount: Int? = nil, periodDays: Int? = nil,
        sentimentComputedAt: String? = nil, userCount: Int? = nil, enabledCount: Int? = nil,
        weeklyActiveCount: Int? = nil, usageAggregatedAt: String? = nil
    ) {
        self.serverKey = serverKey
        self.repositoryURL = repositoryURL
        self.starCount = starCount
        self.forkCount = forkCount
        self.lastCommitDate = lastCommitDate
        self.openIssueCount = openIssueCount
        self.isArchived = isArchived
        self.githubFetchedAt = githubFetchedAt
        self.isTrending = isTrending
        self.trendingScore = trendingScore
        self.sentimentSummary = sentimentSummary
        self.mentionCount = mentionCount
        self.periodDays = periodDays
        self.sentimentComputedAt = sentimentComputedAt
        self.userCount = userCount
        self.enabledCount = enabledCount
        self.weeklyActiveCount = weeklyActiveCount
        self.usageAggregatedAt = usageAggregatedAt
    }
}

// MARK: - CatalogViewModel

struct CatalogViewModel: Identifiable, Sendable {
    let entry: CatalogEntry
    let metrics: ServerMetrics?

    var id: String { entry.id }

    var isTrending: Bool { metrics?.isTrending ?? false }
    var trendingScore: Int? { metrics?.trendingScore }
    var starCount: Int? { metrics?.starCount }
    var lastCommitDate: String? { metrics?.lastCommitDate }
    var userCount: Int? { metrics?.userCount }
    var sentimentSummary: String? { metrics?.sentimentSummary }
    var isAlternative: Bool { entry.alternativeTo != nil }
}

// MARK: - MCPServerConfig convenience init from CatalogEntry

extension MCPServerConfig {
    init(from entry: CatalogEntry) {
        let transport: TransportType = entry.transportType == "http" ? .http : .stdio
        let envVars = entry.envVars.map { envVar -> EnvVar in
            var ev = EnvVar(key: envVar.name, value: "", isSensitive: envVar.isSensitive)
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
