# Private Catalog Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to configure private catalog URLs in Preferences; each URL gets its own tab (named by the catalog JSON) showing internal MCP servers, visible only to users who configure the URL.

**Architecture:** `PrivateCatalogStore` holds a `[PrivateCatalogSource]` fetched from user-configured URLs. `PrivateCatalogPreferences.urls` setter posts a `NotificationCenter` notification so the store re-fetches automatically without any `show()` call-site changes. A new `PrivateCatalogView` displays a single source's entries. `MenuBarView` and `MainWindowView` gain dynamic tabs/sidebar entries driven by `privateCatalogStore.sources`.

**Tech Stack:** Swift / SwiftUI / macOS, `UserDefaults`, `URLSession`, `CryptoKit.SHA256` (stable cache file naming), `NotificationCenter`.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `mcp-inator/Services/PrivateCatalogStore.swift` | Create | `PrivateCatalogPreferences`, `PrivateCatalogResponse`, `PrivateCatalogSource`, `PrivateCatalogStore` |
| `mcp-inator/UI/PrivateCatalogView.swift` | Create | Simplified catalog list (category filter + search; no Featured/Discover) |
| `mcp-inator/UI/CatalogView.swift` | Modify | Remove `private` from `FilterChip` so `PrivateCatalogView` can reuse it |
| `mcp-inator/UI/PreferencesView.swift` | Modify | Add "Private Catalogs" section; increase window height |
| `mcp-inator/UI/MenuBarView.swift` | Modify | Add dynamic private-catalog tabs via `ForEach` over `privateCatalogStore.sources` |
| `mcp-inator/UI/MainWindowView.swift` | Modify | Extend `SidebarSection`; add private-source entries + detail pane |
| `mcp-inator/App/mcp_inatorApp.swift` | Modify | Add `@StateObject privateCatalogStore`; inject; call `fetch()`; wire `MainWindowController` |
| `mcp-inatorTests/Unit/PrivateCatalogStoreTests.swift` | Create | `PrivateCatalogStore` tests |
| `mcp-inatorTests/TestHelpers/MockURLProtocol.swift` | Modify | Add per-URL response data + per-URL status code support |

---

### Task 1: Extend `MockURLProtocol` for per-URL responses

**Files:**
- Modify: `mcp-inatorTests/TestHelpers/MockURLProtocol.swift`

The existing `MockURLProtocol` always returns the same `responseStatusCode` and empty `Data()` for every request. `PrivateCatalogStore` tests need to serve different JSON per URL and simulate per-URL failures.

- [ ] **Step 1: Add two new static fields after the existing ones**

In `MockURLProtocol.swift`, after the existing `static nonisolated(unsafe) var responseStatusCode = 200` line, add:

```swift
static nonisolated(unsafe) var responsesByURL: [String: Data] = [:]
static nonisolated(unsafe) var statusCodesByURL: [String: Int] = [:]
```

- [ ] **Step 2: Update `startLoading()` to use per-URL values**

In `startLoading()`, replace the existing lines:
```swift
let response = HTTPURLResponse(
    url: request.url!,  // swiftlint:disable:this force_unwrapping
    statusCode: MockURLProtocol.responseStatusCode,
    httpVersion: nil,
    headerFields: nil
)!  // swiftlint:disable:this force_unwrapping
client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
client?.urlProtocol(self, didLoad: Data())
client?.urlProtocolDidFinishLoading(self)
```

with:
```swift
let urlKey = request.url?.absoluteString ?? ""
let statusCode = MockURLProtocol.statusCodesByURL[urlKey] ?? MockURLProtocol.responseStatusCode
let responseData = MockURLProtocol.responsesByURL[urlKey] ?? Data()

let response = HTTPURLResponse(
    url: request.url!,  // swiftlint:disable:this force_unwrapping
    statusCode: statusCode,
    httpVersion: nil,
    headerFields: nil
)!  // swiftlint:disable:this force_unwrapping
client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
client?.urlProtocol(self, didLoad: responseData)
client?.urlProtocolDidFinishLoading(self)
```

- [ ] **Step 3: Verify existing tests still pass**

Run: `make cover`
Expected: all existing tests pass — new fields default to `[:]` so prior tests are unaffected.

- [ ] **Step 4: Commit**

```bash
git add mcp-inatorTests/TestHelpers/MockURLProtocol.swift
git commit -m "test: extend MockURLProtocol with per-URL response data and status codes"
```

---

### Task 2: `PrivateCatalogStore` — data model, preferences, and fetch service (TDD)

**Files:**
- Create: `mcp-inator/Services/PrivateCatalogStore.swift`
- Create: `mcp-inatorTests/Unit/PrivateCatalogStoreTests.swift`

- [ ] **Step 1: Write all failing tests**

Create `mcp-inatorTests/Unit/PrivateCatalogStoreTests.swift`:

```swift
import XCTest
@testable import mcp_inator

@MainActor
final class PrivateCatalogStoreTests: XCTestCase {

    private var store: PrivateCatalogStore!
    private var session: URLSession!
    private var cacheDir: URL!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests = []
        MockURLProtocol.responsesByURL = [:]
        MockURLProtocol.statusCodesByURL = [:]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateCatalogTests-\(UUID().uuidString)")
        store = PrivateCatalogStore(session: session, cacheDir: cacheDir)
        UserDefaults.standard.removeObject(forKey: "privateCatalogURLs")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "privateCatalogURLs")
        MockURLProtocol.responsesByURL = [:]
        MockURLProtocol.statusCodesByURL = [:]
        try? FileManager.default.removeItem(at: cacheDir)
        super.tearDown()
    }

    // MARK: - Preferences

    func testPreferences_defaultsToEmptyArray() {
        XCTAssertTrue(PrivateCatalogPreferences.urls.isEmpty)
    }

    // MARK: - fetch() — happy path

    func testFetch_noURLs_sourcesIsEmpty() async {
        await store.fetch()
        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_singleURL_producesOneSource() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test Source")
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].tabName, "Test Source")
        XCTAssertEqual(store.sources[0].url, url)
    }

    func testFetch_singleURL_entriesLoaded() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test", serverKey: "my-server")
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertEqual(store.sources[0].entries.count, 1)
        XCTAssertEqual(store.sources[0].entries[0].entry.serverKey, "my-server")
    }

    // MARK: - fetch() — failures

    func testFetch_serverError_silentlySkipped() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.statusCodesByURL[url] = 500
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_badJSON_silentlySkipped() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = Data("not valid json".utf8)
        PrivateCatalogPreferences.urls = [url]

        await store.fetch()

        XCTAssertTrue(store.sources.isEmpty)
    }

    func testFetch_invalidURL_silentlySkipped() async {
        PrivateCatalogPreferences.urls = ["not a url!!@#$"]
        await store.fetch()
        XCTAssertTrue(store.sources.isEmpty)
    }

    // MARK: - Cache fallback

    func testFetch_fallsBackToCache_whenNetworkFails() async {
        let url = "https://example.com/catalog.json"

        // First fetch: network succeeds → caches result
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Cached Source")
        PrivateCatalogPreferences.urls = [url]
        await store.fetch()
        XCTAssertEqual(store.sources[0].tabName, "Cached Source")

        // Second fetch: network fails → falls back to cache
        MockURLProtocol.responsesByURL.removeValue(forKey: url)
        MockURLProtocol.statusCodesByURL[url] = 500
        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].tabName, "Cached Source")
    }

    // MARK: - Deduplication and ordering

    func testFetch_deduplicatesURLs() async {
        let url = "https://example.com/catalog.json"
        MockURLProtocol.responsesByURL[url] = makeSourceJSON(tabName: "Test")
        PrivateCatalogPreferences.urls = [url, url]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 1)
    }

    func testFetch_preservesConfiguredOrder() async {
        let url1 = "https://example.com/catalog1.json"
        let url2 = "https://example.com/catalog2.json"
        MockURLProtocol.responsesByURL[url1] = makeSourceJSON(tabName: "Source 1")
        MockURLProtocol.responsesByURL[url2] = makeSourceJSON(tabName: "Source 2")
        PrivateCatalogPreferences.urls = [url1, url2]

        await store.fetch()

        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.sources[0].tabName, "Source 1")
        XCTAssertEqual(store.sources[1].tabName, "Source 2")
    }

    // MARK: - Helpers

    private func makeSourceJSON(tabName: String, serverKey: String = "test-server") -> Data {
        let server: [String: Any] = [
            "id": serverKey,
            "displayName": "Test Server",
            "category": "developer-tools",
            "shortDescription": "A test server.",
            "transportType": "stdio",
            "command": "npx",
            "args": ["-y", "test-pkg"],
            "envVars": [] as [Any],
            "isOfficial": false,
            "serverKey": serverKey
        ]
        let json: [String: Any] = ["tabName": tabName, "servers": [server]]
        return try! JSONSerialization.data(withJSONObject: json)  // swiftlint:disable:this force_try
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `make cover`
Expected: `PrivateCatalogStoreTests` fails with "cannot find type 'PrivateCatalogStore' in scope" (the type doesn't exist yet). If XcodeGen hasn't added the test file, run `make cover` once — it regenerates `project.pbxproj` automatically.

- [ ] **Step 3: Create `PrivateCatalogStore.swift`**

Create `mcp-inator/Services/PrivateCatalogStore.swift`:

```swift
import Foundation
import CryptoKit

// MARK: - PrivateCatalogPreferences

enum PrivateCatalogPreferences {
    static let urlsChangedNotification = Notification.Name("privateCatalogURLsChanged")

    static var urls: [String] {
        get { UserDefaults.standard.stringArray(forKey: "privateCatalogURLs") ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: "privateCatalogURLs")
            NotificationCenter.default.post(name: urlsChangedNotification, object: nil)
        }
    }
}

// MARK: - PrivateCatalogResponse

struct PrivateCatalogResponse: Codable {
    let tabName: String
    let servers: [CatalogEntry]
}

// MARK: - PrivateCatalogSource

struct PrivateCatalogSource: Identifiable {
    let url: String
    let tabName: String
    let entries: [CatalogViewModel]

    var id: String { url }
}

// MARK: - PrivateCatalogStore

@MainActor
final class PrivateCatalogStore: ObservableObject {
    @Published private(set) var sources: [PrivateCatalogSource] = []

    private let session: URLSession
    private let cacheDir: URL

    init(session: URLSession = .shared, cacheDir: URL = Self.defaultCacheDir) {
        self.session = session
        self.cacheDir = cacheDir
        NotificationCenter.default.addObserver(
            forName: PrivateCatalogPreferences.urlsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.fetch() }
        }
    }

    static var defaultCacheDir: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("mcp-inator")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Public API

    func fetch() async {
        let deduplicated = deduplicate(PrivateCatalogPreferences.urls)
        var fetched: [PrivateCatalogSource] = []
        await withTaskGroup(of: PrivateCatalogSource?.self) { group in
            for url in deduplicated {
                group.addTask { await self.fetchSource(url: url) }
            }
            for await result in group {
                if let source = result { fetched.append(source) }
            }
        }
        sources = deduplicated.compactMap { url in fetched.first { $0.url == url } }
    }

    // MARK: - Private

    private func fetchSource(url: String) async -> PrivateCatalogSource? {
        guard let requestURL = URL(string: url) else { return nil }
        let request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return loadCachedSource(url: url)
            }
            let decoded = try JSONDecoder().decode(PrivateCatalogResponse.self, from: data)
            saveCache(decoded, for: url)
            return makeSource(response: decoded, url: url)
        } catch {
            return loadCachedSource(url: url)
        }
    }

    private func loadCachedSource(url: String) -> PrivateCatalogSource? {
        guard let cached = loadCache(for: url) else { return nil }
        return makeSource(response: cached, url: url)
    }

    private func makeSource(response: PrivateCatalogResponse, url: String) -> PrivateCatalogSource {
        let entries = response.servers.map { CatalogViewModel(entry: $0, metrics: nil) }
        return PrivateCatalogSource(url: url, tabName: response.tabName, entries: entries)
    }

    private func deduplicate(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func cacheURL(for urlString: String) -> URL {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        let hex = String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
        return cacheDir.appendingPathComponent("private-catalog-\(hex).json")
    }

    private func saveCache(_ response: PrivateCatalogResponse, for urlString: String) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(response) else { return }
        try? data.write(to: cacheURL(for: urlString), options: .atomic)
    }

    private func loadCache(for urlString: String) -> PrivateCatalogResponse? {
        guard let data = try? Data(contentsOf: cacheURL(for: urlString)) else { return nil }
        return try? JSONDecoder().decode(PrivateCatalogResponse.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

Run: `make cover`
Expected: all `PrivateCatalogStoreTests` pass (9 tests).

- [ ] **Step 5: Commit**

```bash
git add mcp-inator/Services/PrivateCatalogStore.swift \
        mcp-inatorTests/Unit/PrivateCatalogStoreTests.swift
git commit -m "feat: add PrivateCatalogStore with preferences, fetch, and cache"
```

---

### Task 3: `PrivateCatalogView` — simplified catalog list view

**Files:**
- Modify: `mcp-inator/UI/CatalogView.swift` (lines 369–390, remove `private` from `FilterChip`)
- Create: `mcp-inator/UI/PrivateCatalogView.swift`

- [ ] **Step 1: Make `FilterChip` accessible to `PrivateCatalogView`**

In `mcp-inator/UI/CatalogView.swift`, find the line:
```swift
private struct FilterChip: View {
```
Change it to:
```swift
struct FilterChip: View {
```

- [ ] **Step 2: Create `PrivateCatalogView.swift`**

Create `mcp-inator/UI/PrivateCatalogView.swift`:

```swift
import SwiftUI

struct PrivateCatalogView: View {
    @EnvironmentObject private var store: ConfigStore

    let entries: [CatalogViewModel]
    let tabTitle: String
    let isCompact: Bool
    @Binding var selectedEntry: CatalogViewModel?

    @State private var searchText: String = ""
    @State private var selectedCategory: CatalogCategory?

    private var usedCategories: [CatalogCategory] {
        let present = Set(entries.map(\.entry.category))
        return CatalogCategory.allCases.filter { present.contains($0) }
    }

    private var sortedEntries: [CatalogViewModel] {
        entries.sorted {
            $0.entry.displayName.localizedCaseInsensitiveCompare($1.entry.displayName) == .orderedAscending
        }
    }

    private var visibleEntries: [CatalogViewModel] {
        let byCategory: [CatalogViewModel]
        if let cat = selectedCategory {
            byCategory = sortedEntries.filter { $0.entry.category == cat }
        } else {
            byCategory = sortedEntries
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return byCategory }
        return byCategory.filter { vm in
            vm.entry.displayName.lowercased().contains(query) ||
            vm.entry.shortDescription.lowercased().contains(query) ||
            vm.entry.category.label.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && visibleEntries.isEmpty {
                emptySearchState
            } else {
                categoryFilterBar
                Divider()
                entryList
            }
        }
        .navigationTitle(tabTitle)
        .searchable(text: $searchText, prompt: "Search \(tabTitle)…")
    }

    // MARK: - Category filter bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(usedCategories) { category in
                    FilterChip(label: category.label, isSelected: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        List {
            Section {
                ForEach(visibleEntries) { vm in entryRow(vm) }
            } header: {
                Text("All Servers")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func entryRow(_ vm: CatalogViewModel) -> some View {
        if isCompact {
            NavigationLink(destination: CatalogEntryDetailView(vm: vm).environmentObject(store)) {
                CatalogRow(vm: vm, showCategory: true, isInLibrary: isInLibrary(vm))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
        } else {
            CatalogRow(vm: vm, showCategory: true, isInLibrary: isInLibrary(vm))
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .contentShape(Rectangle())
                .onTapGesture { selectedEntry = vm }
                .listRowBackground(
                    selectedEntry?.id == vm.id ? Color.accentColor.opacity(0.15) : Color.clear
                )
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "building.2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No servers in this catalog")
                .font(.headline)
            Text("The catalog may still be loading, or the URL returned no servers.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No results")
                .font(.headline)
            Text("No servers matched \"\(searchText)\"")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Clear Search") { searchText = "" }
            Spacer()
        }
        .padding()
    }

    private func isInLibrary(_ vm: CatalogViewModel) -> Bool {
        store.configs.contains { $0.serverKey == vm.entry.serverKey }
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `make cover`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add mcp-inator/UI/CatalogView.swift mcp-inator/UI/PrivateCatalogView.swift
git commit -m "feat: add PrivateCatalogView for private catalog tab display"
```

---

### Task 4: `PreferencesView` — private catalogs section

**Files:**
- Modify: `mcp-inator/UI/PreferencesView.swift`
- Modify: `mcp-inator/App/mcp_inatorApp.swift` (window height only — in `PreferencesWindowController.show()`)

`PreferencesView` reads/writes `PrivateCatalogPreferences.urls` directly. The setter posts a `NotificationCenter` notification; `PrivateCatalogStore` listens and re-fetches automatically. No `@EnvironmentObject` injection into `PreferencesView` is needed.

- [ ] **Step 1: Add state variables to `PreferencesView`**

In `PreferencesView`, after the existing `@AppStorage("sharingConsented")` line, add:

```swift
@State private var privateCatalogURLs: [String] = []
@State private var newCatalogURL: String = ""
```

- [ ] **Step 2: Load URLs on appear**

The `Form` currently ends with `.formStyle(.grouped).frame(width: 360).padding()`. Add `.onAppear` to load the current URLs:

```swift
.formStyle(.grouped)
.frame(width: 360)
.padding()
.onAppear {
    privateCatalogURLs = PrivateCatalogPreferences.urls
}
```

- [ ] **Step 3: Add the "Private Catalogs" section**

Inside the `Form { }`, after the existing `Section("General") { ... }` block, add:

```swift
Section("Private Catalogs") {
    Text("Add a URL to a private catalog JSON file. Each source gets its own tab in the Catalog view.")
        .foregroundColor(.secondary)
        .font(.callout)

    ForEach(Array(privateCatalogURLs.enumerated()), id: \.offset) { index, url in
        HStack {
            Text(url)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                privateCatalogURLs.remove(at: index)
                PrivateCatalogPreferences.urls = privateCatalogURLs
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    HStack {
        TextField("https://example.com/catalog.json", text: $newCatalogURL)
        Button("Add") {
            let trimmed = newCatalogURL.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            privateCatalogURLs.append(trimmed)
            PrivateCatalogPreferences.urls = privateCatalogURLs
            newCatalogURL = ""
        }
        .disabled(newCatalogURL.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
```

- [ ] **Step 4: Increase the Preferences window height**

In `mcp_inatorApp.swift`, inside `PreferencesWindowController.show()`, find:
```swift
win.setContentSize(NSSize(width: 400, height: 280))
```
Change it to:
```swift
win.setContentSize(NSSize(width: 400, height: 430))
```

- [ ] **Step 5: Verify it builds**

Run: `make cover`
Expected: build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add mcp-inator/UI/PreferencesView.swift mcp-inator/App/mcp_inatorApp.swift
git commit -m "feat: add private catalogs section to Preferences"
```

---

### Task 5: App wiring — inject `PrivateCatalogStore` into the app

**Files:**
- Modify: `mcp-inator/App/mcp_inatorApp.swift`

This task wires `PrivateCatalogStore` into the app entry point so it's available as `@EnvironmentObject` in both `MenuBarView` and `MainWindowView`, and its `fetch()` is called at launch.

- [ ] **Step 1: Add `@StateObject` for `privateCatalogStore`**

In `mcp_inatorApp`, after the existing `@StateObject private var catalogStore = CatalogStore()` line, add:

```swift
@StateObject private var privateCatalogStore = PrivateCatalogStore()
```

- [ ] **Step 2: Inject into `MenuBarView`**

In the `MenuBarExtra` content block, the existing `.environmentObject(catalogStore)` modifier is near the bottom of the `MenuBarView()` chain. Add `.environmentObject(privateCatalogStore)` directly after it:

```swift
.environmentObject(catalogStore)
.environmentObject(privateCatalogStore)
```

- [ ] **Step 3: Call `fetch()` at launch — menu bar mode**

In `MenuBarExtra`'s `onAppear` block (the one with `wireWindowController()`, `store.seedSelfEntry()`, etc.), add after the existing `Task { await catalogStore.fetchIfNeeded() }` line:

```swift
Task { await privateCatalogStore.fetch() }
```

- [ ] **Step 4: Call `fetch()` at launch — dock mode label**

In the `label` image's `onAppear` block, add after the existing `Task { await catalogStore.fetchIfNeeded() }` line:

```swift
Task { await privateCatalogStore.fetch() }
```

- [ ] **Step 5: Add `privateCatalogStore` to `MainWindowController`**

In `MainWindowController`, after `private weak var catalogStore: CatalogStore?`, add:

```swift
private weak var privateCatalogStore: PrivateCatalogStore?
```

Update `configure()` — add `privateCatalogStore: PrivateCatalogStore` as a new parameter after `catalogStore`:

```swift
// swiftlint:disable:next function_parameter_count
func configure(
    appModeManager: AppModeManager,
    storeContainer: StoreContainer,
    registryStore: RegistryStore,
    catalogStore: CatalogStore,
    privateCatalogStore: PrivateCatalogStore,
    updater: SPUUpdater,
    aboutController: AboutWindowController
) {
    self.appModeManager = appModeManager
    self.storeContainer = storeContainer
    self.registryStore = registryStore
    self.catalogStore = catalogStore
    self.privateCatalogStore = privateCatalogStore
    self.updater = updater
    self.aboutController = aboutController
}
```

- [ ] **Step 6: Inject into `MainWindowView` inside `open()`**

In `MainWindowController.open()`, update the guard to include `privateCatalogStore`:

```swift
guard let appModeManager,
      let storeContainer,
      let registryStore,
      let catalogStore,
      let privateCatalogStore,
      let updater,
      let aboutController else { return }
```

And in the `let view = MainWindowView()...` chain, add `.environmentObject(privateCatalogStore)` after `.environmentObject(catalogStore)`:

```swift
let view = MainWindowView()
    .environmentObject(appModeManager)
    .environmentObject(storeContainer)
    .environmentObject(registryStore)
    .environmentObject(catalogStore)
    .environmentObject(privateCatalogStore)
    .environment(\.openAboutWindow, { [weak aboutController] in
        Task { @MainActor in
            aboutController?.show(updater: updater)
        }
    })
```

- [ ] **Step 7: Update `wireWindowController()` call site**

In `wireWindowController()`, update the `mainWindowController.configure(...)` call to pass `privateCatalogStore`:

```swift
mainWindowController.configure(
    appModeManager: appModeManager,
    storeContainer: storeContainer,
    registryStore: registryStore,
    catalogStore: catalogStore,
    privateCatalogStore: privateCatalogStore,
    updater: updaterController.updater,
    aboutController: aboutController
)
```

- [ ] **Step 8: Verify it builds**

Run: `make cover`
Expected: build succeeds, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add mcp-inator/App/mcp_inatorApp.swift
git commit -m "feat: wire PrivateCatalogStore into app entry point"
```

---

### Task 6: `MenuBarView` — dynamic private catalog tabs

**Files:**
- Modify: `mcp-inator/UI/MenuBarView.swift`

- [ ] **Step 1: Add `@EnvironmentObject` for `privateCatalogStore`**

In `MenuBarView`, after the existing `@EnvironmentObject var registryStore: RegistryStore` line, add:

```swift
@EnvironmentObject var privateCatalogStore: PrivateCatalogStore
```

- [ ] **Step 2: Add dynamic private-catalog tabs inside `TabView`**

In `MenuBarView.body`, the `TabView { }` currently contains three static tabs (Servers, Agents, Catalog). After the closing `}` of the Catalog tab (but still inside `TabView { }`), add:

```swift
ForEach(privateCatalogStore.sources) { source in
    NavigationStack {
        PrivateCatalogView(
            entries: source.entries,
            tabTitle: source.tabName,
            isCompact: true,
            selectedEntry: .constant(nil)
        )
        .environmentObject(store)
    }
    .environment(\.navigationIsCompact, true)
    .tabItem {
        Label(source.tabName, systemImage: "building.2")
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `make cover`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add mcp-inator/UI/MenuBarView.swift
git commit -m "feat: add dynamic private catalog tabs to MenuBarView"
```

---

### Task 7: `MainWindowView` — dynamic private sidebar entries and detail pane

**Files:**
- Modify: `mcp-inator/UI/MainWindowView.swift`

- [ ] **Step 1: Extend `SidebarSection` to support private sources**

Replace the existing enum definition:
```swift
enum SidebarSection: String, Hashable {
    case servers, agents, catalog
}
```
with:
```swift
enum SidebarSection: Hashable {
    case servers, agents, catalog
    case privateSource(String) // String = URL of the private catalog source
}
```

- [ ] **Step 2: Add `@EnvironmentObject` and new state variable**

In `MainWindowView`, after `@EnvironmentObject private var catalogStore: CatalogStore`, add:

```swift
@EnvironmentObject private var privateCatalogStore: PrivateCatalogStore
```

And after `@State private var selectedCatalogEntry: CatalogViewModel?`, add:

```swift
@State private var selectedPrivateEntry: CatalogViewModel?
```

- [ ] **Step 3: Add private sources to the sidebar list**

In the `NavigationSplitView` sidebar `List { }`, after the existing `Label("Catalog", ...)` entry, add:

```swift
if !privateCatalogStore.sources.isEmpty {
    Section("Private") {
        ForEach(privateCatalogStore.sources) { source in
            Label(source.tabName, systemImage: "building.2")
                .tag(SidebarSection.privateSource(source.url))
        }
    }
}
```

- [ ] **Step 4: Handle `.privateSource` in the content pane**

In the `content: { }` block's `switch selectedSection { }`, add after the `case .catalog:` block:

```swift
case .privateSource(let url):
    if let source = privateCatalogStore.sources.first(where: { $0.url == url }) {
        NavigationStack {
            PrivateCatalogView(
                entries: source.entries,
                tabTitle: source.tabName,
                isCompact: false,
                selectedEntry: $selectedPrivateEntry
            )
            .environmentObject(store)
        }
    }
```

- [ ] **Step 5: Handle `.privateSource` in the detail pane**

In the `detail: { }` block's `switch selectedSection { }`, add after the `case .catalog:` block:

```swift
case .privateSource:
    if let entry = selectedPrivateEntry {
        NavigationStack {
            CatalogEntryDetailView(vm: entry)
                .environmentObject(store)
        }
        .id(entry.id)
    } else {
        DetailPlaceholderView(
            systemImage: "building.2",
            message: "Select a server from the catalog"
        )
    }
```

- [ ] **Step 6: Verify it builds and run full test suite**

Run: `make cover`
Expected: build succeeds, all tests pass.

- [ ] **Step 7: Run lint**

Run: `make lint`
Expected: no warnings.

- [ ] **Step 8: Bump version and update release notes**

In `VERSION`, increment the patch version (e.g. `0.5.4` → `0.5.5`).

In `RELEASE_NOTES.md`, prepend a new entry:

```markdown
## 0.5.5

- Private catalog sources: configure additional catalog URLs in Preferences to add internal MCP servers as a separate tab
```

- [ ] **Step 9: Commit**

```bash
git add mcp-inator/UI/MainWindowView.swift VERSION RELEASE_NOTES.md
git commit -m "feat: add private catalog sources — dynamic sidebar + detail in dock mode"
```
