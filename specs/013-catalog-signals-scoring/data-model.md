# Data Model: Catalog Signals & Scoring

## servers.json (mcp-catalog) — schema version 3

New fields added to each entry. All existing fields preserved except `isVerified` (removed) and `isFirstParty` (renamed → `isOfficial`).

```json
{
  "id": "github",
  "displayName": "GitHub",
  "category": "developer-tools",       // NEW taxonomy (was "Code & Development")
  "isOfficial": true,                   // NEW — replaces isFirstParty
  "relatedApp": "GitHub Desktop",       // NEW — macOS app name or null
  "editorialRank": null,                // NEW — int pin or null

  // Removed:
  // "isVerified": true  ← removed
  // "isFirstParty": false  ← renamed to isOfficial

  // Unchanged:
  "shortDescription": "...",
  "curatorNote": "...",
  "transportType": "stdio",
  "command": "npx",
  "args": [...],
  "url": "",
  "envVars": [...],
  "requiredArgs": [...],
  "documentationURL": "...",
  "repositoryURL": "...",
  "alternativeTo": null,
  "serverKey": "github"
}
```

**New entry — moov-docs (editorial, pinned):**

```json
{
  "id": "moov-docs",
  "displayName": "Moov",
  "category": "finance",
  "shortDescription": "Access Moov financial infrastructure documentation and API reference.",
  "curatorNote": "Moov provides open-source financial infrastructure. This server exposes their full documentation via a hosted MCP endpoint.",
  "transportType": "stdio",
  "command": "npx",
  "args": ["-y", "mcp-remote", "https://docs.moov.io/mcp"],
  "url": "",
  "envVars": [],
  "requiredArgs": [],
  "documentationURL": "https://docs.moov.io",
  "repositoryURL": null,
  "isOfficial": true,
  "relatedApp": null,
  "editorialRank": 1,
  "alternativeTo": null,
  "serverKey": "moov-docs"
}
```

Signal fields will all be null (no npm package, no Docker image, no GitHub repo). `editorialRank: 1` ensures it surfaces at the top regardless of score.

---

**`relatedApp` values for existing entries:**

| id | relatedApp |
|----|-----------|
| github | "GitHub Desktop" |
| slack | "Slack" |
| notion | "Notion" |
| linear | "Linear" |
| google-drive | "Google Drive" |
| docker | "Docker" |
| home-assistant | null |
| (all others) | null |

---

## stats.json (mcp-catalog) — schema version 3

New fields added to each `ServerMetrics` entry. All existing fields preserved.

```json
{
  "serverKey": "github",
  "repositoryURL": "https://github.com/modelcontextprotocol/servers",

  // Existing fields (unchanged):
  "isTrending": false,
  "starCount": 86490,
  "forkCount": 10870,
  "openIssueCount": 492,
  "isArchived": false,
  "lastCommitDate": "2026-05-30T18:35:20Z",
  "githubFetchedAt": "2026-05-31T01:45:55Z",

  // NEW signal fields (written by enrich.py):
  "githubStarsIsShared": true,          // true when multiple entries share this repo URL
  "githubCommits90d": 4,                // commits in last 90 days, path-filtered for mono-repos
  "npmWeeklyDownloads": 145230,         // null if not on npm
  "pypiMonthlyDownloads": null,         // null if not on PyPI
  "dockerTotalPulls": 116000,           // null if no Docker image
  "smitheryUseCount": 3873,             // null if not found on Smithery (capped at 100k in scoring)
  "baseScore": 35.9,                    // computed by enrich.py, see scoring formula
  "signalsRefreshedAt": "2026-06-01T04:12:33Z"
}
```

---

## Swift: CatalogEntry (mcp-inator/Models/CatalogEntry.swift)

Changes to the existing struct:

```swift
struct CatalogEntry: Identifiable, Codable, Sendable {
    // New fields:
    var isOfficial: Bool          // replaces isFirstParty
    var relatedApp: String?       // macOS app name for installed-app boost
    var editorialRank: Int?       // pin to top of sort; nil = use score

    // Removed:
    // var isVerified: Bool       ← removed
    // var isFirstParty: Bool     ← renamed to isOfficial

    // All other fields unchanged.
}
```

Decoder handles backward compatibility:
```swift
// In init(from decoder:):
isOfficial = (try? container.decodeIfPresent(Bool.self, forKey: .isOfficial))
          ?? (try? container.decodeIfPresent(Bool.self, forKey: .isFirstParty))
          ?? false
```

---

## Swift: CatalogCategory (mcp-inator/Models/CatalogEntry.swift)

Enum raw values updated to new slug taxonomy. Custom `init(from:)` handles old display-string values for backward compatibility with cached entries.

```swift
enum CatalogCategory: String, Codable, CaseIterable, Identifiable {
    case developerTools = "developer-tools"
    case searchWeb      = "search-web"
    case databases      = "databases"
    case productivity   = "productivity"
    case aiMemory       = "ai-memory"
    case infrastructure = "infrastructure"
    case finance        = "finance"

    // display label (for UI, separate from rawValue)
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
}
```

---

## Swift: ServerMetrics (mcp-inator/Models/CatalogEntry.swift)

New fields appended to existing struct:

```swift
struct ServerMetrics: Codable, Sendable {
    // Existing fields unchanged ...

    // New:
    var githubStarsIsShared: Bool?
    var githubCommits90d: Int?
    var npmWeeklyDownloads: Int?
    var pypiMonthlyDownloads: Int?
    var dockerTotalPulls: Int?
    var smitheryUseCount: Int?
    var baseScore: Double?
    var signalsRefreshedAt: String?
}
```

---

## Swift: CatalogViewModel (mcp-inator/Models/CatalogEntry.swift)

New computed properties:

```swift
struct CatalogViewModel: Identifiable, Sendable {
    let entry: CatalogEntry
    let metrics: ServerMetrics?
    let installedApps: Set<String>   // injected from CatalogStore at init

    // Existing:
    var isOfficial: Bool  { entry.isOfficial }

    // New — display score with installed-app personalization:
    var displayScore: Double {
        let base = metrics?.baseScore ?? 0
        let appBoost = entry.relatedApp.map { installedApps.contains($0.lowercased()) ? 3.0 : 0.0 } ?? 0.0
        return base + appBoost
    }

    // New — amber stale warning (>6 months since last push):
    var isStale: Bool {
        guard let dateStr = metrics?.lastCommitDate,
              let date = ISO8601DateFormatter().date(from: dateStr) else { return false }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0 > 180
    }

    // New — install count for display (prefer npm weekly, fall back to docker):
    var installCount: Int?  { metrics?.npmWeeklyDownloads ?? metrics?.dockerTotalPulls }
    var installCountLabel: String? {
        guard let n = installCount else { return nil }
        return formatCount(n) + (metrics?.npmWeeklyDownloads != nil ? "/wk" : " pulls")
    }

    // New — stars display (with "repo" qualifier when shared):
    var starsIsShared: Bool { metrics?.githubStarsIsShared ?? false }
}
```

---

## Swift: CatalogStore (mcp-inator/Services/CatalogStore.swift)

New property and updated `fetchIfNeeded`:

```swift
@MainActor
final class CatalogStore: ObservableObject {
    // New:
    private let installedApps: Set<String>

    init(client: ...) {
        self.installedApps = Self.scanInstalledApps()
        // ...
    }

    // New static helper:
    private static func scanInstalledApps() -> Set<String> {
        let paths = ["/Applications", ("~/Applications" as NSString).expandingTildeInPath]
        var names = Set<String>()
        for path in paths {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for item in items where item.hasSuffix(".app") {
                names.insert(item.replacingOccurrences(of: ".app", with: "").lowercased())
            }
        }
        return names
    }

    // Updated — inject installedApps into each CatalogViewModel:
    func fetchIfNeeded() async {
        // ...
        viewModels = entries.map { entry in
            CatalogViewModel(entry: entry,
                             metrics: metrics[entry.serverKey],
                             installedApps: installedApps)
        }
    }

    // Top servers not yet in the user's library — powers the Discover section.
    // Primary: non-editorial entries not in library, score-ordered.
    // Fallback: if none qualify (user has added everything), include editorial entries not in library.
    // Always returns up to 5 entries; never returns empty as long as any entry is outside the library.
    func discoverEntries(libraryKeys: Set<String>) -> [CatalogViewModel] {
        let primary = sortedEntries.filter {
            !libraryKeys.contains($0.entry.serverKey) && $0.entry.editorialRank == nil
        }
        if !primary.isEmpty { return Array(primary.prefix(5)) }
        return Array(sortedEntries
            .filter { !libraryKeys.contains($0.entry.serverKey) }
            .prefix(5))
    }

    // Editorial rank first, then displayScore descending:
    var sortedEntries: [CatalogViewModel] {
        viewModels
            .filter { !$0.isAlternative }
            .sorted { a, b in
                switch (a.entry.editorialRank, b.entry.editorialRank) {
                case let (r1?, r2?): return r1 < r2
                case (_?, nil):     return true
                case (nil, _?):     return false
                default:            return a.displayScore > b.displayScore
                }
            }
    }
}
```

---

## CatalogRow UI Changes (mcp-inator/UI/CatalogView.swift)

The signal display row beneath `displayName`:

```swift
// Replace existing stars + age HStack with:
HStack(spacing: 8) {
    if entry.isOfficial {
        OfficialBadge()                         // renamed from FirstPartyBadge, same visual
    }
    if let count = vm.installCountLabel {
        Label(count, systemImage: "arrow.down.circle")
            .font(.caption2).foregroundColor(.secondary)
    }
    if let stars = vm.starCount {
        Label(formatStars(stars) + (vm.starsIsShared ? " repo" : ""),
              systemImage: "star")
            .font(.caption2).foregroundColor(.secondary)
    }
    if vm.isStale {
        Label("Low activity", systemImage: "exclamationmark.triangle")
            .font(.caption2).foregroundColor(.orange)
    }
}
```

The `CatalogView` browse section replaces the `trendingEntries` section with an `editorialEntries` section (entries with non-null `editorialRank`) and replaces category grouping with a flat sorted list using `sortedEntries`.
