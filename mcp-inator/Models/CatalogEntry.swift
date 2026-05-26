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

// MARK: - CatalogEnvVar

struct CatalogEnvVar: Codable, Identifiable {
    var name: String
    var description: String
    var isRequired: Bool
    var isSensitive: Bool
    var defaultValue: String?

    var id: String { name }
}

// MARK: - CatalogEntry

struct CatalogEntry: Codable, Identifiable {
    var id: String
    var displayName: String
    var category: CatalogCategory
    var shortDescription: String
    var transportType: TransportType
    var command: String
    var args: [String]
    var url: String
    var envVars: [CatalogEnvVar]
    var documentationURL: String?
    var repositoryURL: String?
    var isVerified: Bool
    var serverKey: String

    var isHTTP: Bool { transportType == .http || transportType == .sse }
}

// MARK: - CatalogMetadata

struct CatalogMetadata: Codable {
    var schemaVersion: String
    var bundledAt: Date
    var lastRefreshedAt: Date?
    var entryCount: Int
}

// MARK: - Catalog

struct Catalog: Codable {
    var metadata: CatalogMetadata
    var entries: [CatalogEntry]

    static let supportedSchemaVersion = "1"
}
