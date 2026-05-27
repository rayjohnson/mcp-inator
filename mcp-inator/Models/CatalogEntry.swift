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
