import Foundation

// MARK: - CatalogCategory

enum CatalogCategory: String, Codable, CaseIterable, Identifiable {
    case developerTools = "developer-tools"
    case searchWeb      = "search-web"
    case databases      = "databases"
    case productivity   = "productivity"
    case aiMemory       = "ai-memory"
    case infrastructure = "infrastructure"
    case finance        = "finance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .developerTools: return "Developer Tools"
        case .searchWeb:      return "Search & Web"
        case .databases:      return "Databases"
        case .productivity:   return "Productivity"
        case .aiMemory:       return "AI & Memory"
        case .infrastructure: return "Infrastructure"
        case .finance:        return "Finance"
        }
    }

    // Backward-compat: accept old display-string values from cached entries.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let match = CatalogCategory(rawValue: raw) {
            self = match
            return
        }
        switch raw {
        case "Code & Development":        self = .developerTools
        case "Web & Browser":             self = .searchWeb
        case "Data & Analytics":          self = .databases
        case "Communication",
             "Productivity, Communication": self = .productivity
        case "AI & LLMs":                 self = .aiMemory
        case "Productivity":              self = .productivity
        case "Infrastructure":            self = .infrastructure
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown CatalogCategory: \(raw)"
            )
        }
    }
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
    var isOfficial: Bool
    var relatedApp: String?
    var editorialRank: Int?
    var alternativeTo: String?
    var serverKey: String

    enum CodingKeys: String, CodingKey {
        case id, displayName, category, shortDescription, curatorNote
        case transportType, command, args, url, envVars, requiredArgs
        case documentationURL, repositoryURL
        case isOfficial, isFirstParty          // isFirstParty kept for backward-compat decode
        case relatedApp, editorialRank
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
        // isOfficial: prefer new key, fall back to legacy isFirstParty
        isOfficial = (try? container.decodeIfPresent(Bool.self, forKey: .isOfficial))
                  ?? (try? container.decodeIfPresent(Bool.self, forKey: .isFirstParty))
                  ?? false
        relatedApp = try container.decodeIfPresent(String.self, forKey: .relatedApp)
        editorialRank = try container.decodeIfPresent(Int.self, forKey: .editorialRank)
        alternativeTo = try container.decodeIfPresent(String.self, forKey: .alternativeTo)
        serverKey = try container.decode(String.self, forKey: .serverKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(category, forKey: .category)
        try container.encode(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(curatorNote, forKey: .curatorNote)
        try container.encode(transportType, forKey: .transportType)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(envVars, forKey: .envVars)
        try container.encodeIfPresent(requiredArgs, forKey: .requiredArgs)
        try container.encodeIfPresent(documentationURL, forKey: .documentationURL)
        try container.encodeIfPresent(repositoryURL, forKey: .repositoryURL)
        try container.encode(isOfficial, forKey: .isOfficial)
        try container.encodeIfPresent(relatedApp, forKey: .relatedApp)
        try container.encodeIfPresent(editorialRank, forKey: .editorialRank)
        try container.encodeIfPresent(alternativeTo, forKey: .alternativeTo)
        try container.encode(serverKey, forKey: .serverKey)
    }

    init(
        id: String, displayName: String, category: CatalogCategory,
        shortDescription: String, curatorNote: String? = nil,
        transportType: String = "stdio", command: String = "", args: [String] = [],
        url: String? = nil, envVars: [EnvVarDefinition] = [], requiredArgs: [RequiredArgDefinition]? = nil,
        documentationURL: String? = nil, repositoryURL: String? = nil,
        isOfficial: Bool = false, relatedApp: String? = nil, editorialRank: Int? = nil,
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
        self.isOfficial = isOfficial
        self.relatedApp = relatedApp
        self.editorialRank = editorialRank
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
    // Signal fields (written by signals.py)
    var githubStarsIsShared: Bool?
    var githubCommits90d: Int?
    var npmWeeklyDownloads: Int?
    var pypiMonthlyDownloads: Int?
    var dockerTotalPulls: Int?
    var smitheryUseCount: Int?
    var baseScore: Double?
    var signalsRefreshedAt: String?

    enum CodingKeys: String, CodingKey {
        case serverKey, repositoryURL, starCount, forkCount, lastCommitDate
        case openIssueCount, isArchived, githubFetchedAt, isTrending
        case trendingScore, sentimentSummary, mentionCount, periodDays
        case sentimentComputedAt, userCount, enabledCount, weeklyActiveCount
        case usageAggregatedAt
        case githubStarsIsShared, githubCommits90d
        case npmWeeklyDownloads, pypiMonthlyDownloads, dockerTotalPulls
        case smitheryUseCount, baseScore, signalsRefreshedAt
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
        githubStarsIsShared = try container.decodeIfPresent(Bool.self, forKey: .githubStarsIsShared)
        githubCommits90d = try container.decodeIfPresent(Int.self, forKey: .githubCommits90d)
        npmWeeklyDownloads = try container.decodeIfPresent(Int.self, forKey: .npmWeeklyDownloads)
        pypiMonthlyDownloads = try container.decodeIfPresent(Int.self, forKey: .pypiMonthlyDownloads)
        dockerTotalPulls = try container.decodeIfPresent(Int.self, forKey: .dockerTotalPulls)
        smitheryUseCount = try container.decodeIfPresent(Int.self, forKey: .smitheryUseCount)
        baseScore = try container.decodeIfPresent(Double.self, forKey: .baseScore)
        signalsRefreshedAt = try container.decodeIfPresent(String.self, forKey: .signalsRefreshedAt)
    }

    init(
        serverKey: String, repositoryURL: String? = nil,
        starCount: Int? = nil, forkCount: Int? = nil, lastCommitDate: String? = nil,
        openIssueCount: Int? = nil, isArchived: Bool = false, githubFetchedAt: String? = nil,
        isTrending: Bool = false, trendingScore: Int? = nil,
        sentimentSummary: String? = nil, mentionCount: Int? = nil, periodDays: Int? = nil,
        sentimentComputedAt: String? = nil, userCount: Int? = nil, enabledCount: Int? = nil,
        weeklyActiveCount: Int? = nil, usageAggregatedAt: String? = nil,
        githubStarsIsShared: Bool? = nil, githubCommits90d: Int? = nil,
        npmWeeklyDownloads: Int? = nil, pypiMonthlyDownloads: Int? = nil,
        dockerTotalPulls: Int? = nil, smitheryUseCount: Int? = nil,
        baseScore: Double? = nil, signalsRefreshedAt: String? = nil
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
        self.githubStarsIsShared = githubStarsIsShared
        self.githubCommits90d = githubCommits90d
        self.npmWeeklyDownloads = npmWeeklyDownloads
        self.pypiMonthlyDownloads = pypiMonthlyDownloads
        self.dockerTotalPulls = dockerTotalPulls
        self.smitheryUseCount = smitheryUseCount
        self.baseScore = baseScore
        self.signalsRefreshedAt = signalsRefreshedAt
    }
}

// MARK: - CatalogViewModel

struct CatalogViewModel: Identifiable, Sendable {
    let entry: CatalogEntry
    let metrics: ServerMetrics?
    let installedApps: Set<String>

    init(entry: CatalogEntry, metrics: ServerMetrics?, installedApps: Set<String> = []) {
        self.entry = entry
        self.metrics = metrics
        self.installedApps = installedApps
    }

    var id: String { entry.id }

    // Existing passthrough properties
    var isTrending: Bool { metrics?.isTrending ?? false }
    var trendingScore: Int? { metrics?.trendingScore }
    var starCount: Int? { metrics?.starCount }
    var lastCommitDate: String? { metrics?.lastCommitDate }
    var userCount: Int? { metrics?.userCount }
    var sentimentSummary: String? { metrics?.sentimentSummary }
    var isAlternative: Bool { entry.alternativeTo != nil }

    // New signal properties
    var isOfficial: Bool { entry.isOfficial }
    var starsIsShared: Bool { metrics?.githubStarsIsShared ?? false }

    var displayScore: Double {
        let base = metrics?.baseScore ?? 0
        let boost = entry.relatedApp.map {
            installedApps.contains($0.lowercased()) ? 3.0 : 0.0
        } ?? 0.0
        return base + boost
    }

    var isStale: Bool {
        guard let dateStr = metrics?.lastCommitDate else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateStr)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateStr)
        }
        guard let date else { return false }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return days > 180
    }

    var installCount: Int? {
        metrics?.npmWeeklyDownloads ?? metrics?.dockerTotalPulls
    }

    var installCountLabel: String? {
        guard let count = installCount else { return nil }
        let suffix = metrics?.npmWeeklyDownloads != nil ? "/wk" : " pulls"
        return formatCount(count) + suffix
    }
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

// MARK: - Formatting helper

func formatCount(_ count: Int) -> String {
    switch count {
    case 0..<1_000: return "\(count)"
    case 1_000..<10_000: return String(format: "%.1fk", Double(count) / 1_000)
    case 10_000..<1_000_000: return "\(count / 1_000)k"
    default: return String(format: "%.1fM", Double(count) / 1_000_000)
    }
}
