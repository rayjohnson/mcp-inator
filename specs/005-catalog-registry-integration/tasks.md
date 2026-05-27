# Tasks: Catalog Registry Integration

**Branch**: `005-catalog-registry-integration`
**Input**: [plan.md](plan.md) | [spec.md](spec.md) | [data-model.md](data-model.md) | [research.md](research.md) | [contracts/registry-client.md](contracts/registry-client.md)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no incomplete dependencies)
- **[US1]–[US4]**: User story label (story phases only)
- Tests are explicitly included — quality is a first-class requirement for this feature

---

## Phase 1: Setup

**Purpose**: Create file stubs for all new types and the test fixture. No deletions yet — files that reference CatalogStore still compile until Phase 7 swaps them out.

- [ ] T001 [P] Create `mcp-inatorTests/Fixtures/registry-response.json` with a realistic 3-entry sample registry API response (one npm stdio entry with env vars, one HTTP remote entry with headers, one non-actionable entry with no packages/remotes); add to the test target in Xcode
- [ ] T002 [P] Create stub `mcp-inator/Services/RegistryClient.swift` containing only `import Foundation` and a `// TODO: implement` comment; add to the app target in Xcode
- [ ] T003 [P] Create stub `mcp-inator/Services/RegistryStore.swift` containing only `import Foundation` and `import Combine` and a `// TODO: implement` comment; add to the app target in Xcode
- [ ] T004 [P] Create stub `mcp-inator/Models/RegistryEntry.swift` containing only `import Foundation` and a `// TODO: implement` comment; add to the app target in Xcode
- [ ] T005 [P] Create stub `mcp-inatorTests/Unit/RegistryClientTests.swift` with an empty `@MainActor final class RegistryClientTests: XCTestCase {}`; add to the test target in Xcode
- [ ] T006 [P] Create stub `mcp-inatorTests/Unit/RegistryEntryTests.swift` with an empty `final class RegistryEntryTests: XCTestCase {}`; add to the test target in Xcode
- [ ] T007 [P] Create stub `mcp-inatorTests/Unit/RegistryStoreTests.swift` with an empty `@MainActor final class RegistryStoreTests: XCTestCase {}`; add to the test target in Xcode

**Checkpoint**: Project compiles. All stubs present. Fixture file valid JSON.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Pure types and functions that every subsequent phase depends on. Tests are written alongside implementation — the pure functions are the ideal target for test-first development in this feature.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Raw API Decode Layer

- [ ] T008 Implement all raw API decode structs in `mcp-inator/Services/RegistryClient.swift`: `RegistryAPIResponse`, `RegistryAPIServerWrapper` (with `_meta` CodingKey), `RegistryAPIServer`, `RegistryAPIPackage`, `RegistryAPITransport`, `RegistryAPIRemote`, `RegistryAPIEnvVar`, `RegistryAPIMeta` (with `io.modelcontextprotocol.registry/official` CodingKey), `RegistryAPIOfficialMeta`, `RegistryAPIMetadata`, `RegistryAPIRepository` — all `Decodable`, none public beyond the file
- [ ] T009 [P] Write fixture JSON decode tests in `mcp-inatorTests/Unit/RegistryClientTests.swift`: decode `registry-response.json` fixture into `RegistryAPIResponse`; assert `servers.count == 3`; assert `_meta.official.isLatest` values match fixture; assert `packages[0].environmentVariables` decoded correctly for the npm entry; assert `remotes[0].headers` decoded correctly for the HTTP entry

### Transformation Functions

- [ ] T010 Implement `filterLatest(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]` free function in `mcp-inator/Services/RegistryClient.swift`: keep only entries where `_meta.official.isLatest == true`
- [ ] T011 Implement `deduplicate(_ wrappers: [RegistryAPIServerWrapper]) -> [RegistryAPIServerWrapper]` free function in `mcp-inator/Services/RegistryClient.swift`: keep first occurrence per `server.name`
- [ ] T012 [P] Write `filterLatest` and `deduplicate` unit tests in `mcp-inatorTests/Unit/RegistryClientTests.swift`: filterLatest removes non-latest, keeps latest; deduplicate keeps first of duplicates; both on the same name with mixed isLatest values; empty input returns empty

### RegistryClient Protocol & Production Implementation

- [ ] T013 Implement `RegistryClient` protocol in `mcp-inator/Services/RegistryClient.swift`: `protocol RegistryClient: Sendable { func search(query: String, pageSize: Int) async throws -> [RegistryEntry] }`
- [ ] T014 Implement `URLSessionRegistryClient: RegistryClient` in `mcp-inator/Services/RegistryClient.swift`: `init(session: URLSession = .shared)`; `search(query:pageSize:)` builds `https://registry.modelcontextprotocol.io/v0/servers?search=<q>&pageSize=<n>`, fetches, decodes `RegistryAPIResponse`, applies `filterLatest` + `deduplicate`, maps through `RegistryEntry.init?(raw:)`, returns non-nil results (empty array if all filtered)
- [ ] T015 [P] Write `URLSessionRegistryClient` decode-path tests in `mcp-inatorTests/Unit/RegistryClientTests.swift`: use a mock `URLSession` or `URLProtocol` stub returning the fixture JSON; assert returned `[RegistryEntry]` has correct count after filtering non-latest and non-actionable entries

### App Model: RegistryEntry

- [ ] T016 [P] Implement `PackageType` enum in `mcp-inator/Models/RegistryEntry.swift`: `enum PackageType: String, Codable { case npm, pypi, oci }`
- [ ] T017 [P] Implement `RemoteTransportType` enum in `mcp-inator/Models/RegistryEntry.swift`: `enum RemoteTransportType: String, Codable { case streamableHTTP = "streamable-http"; case sse }`
- [ ] T018 [P] Implement `RegistryEnvVar: Equatable, Codable` struct in `mcp-inator/Models/RegistryEntry.swift`: `name: String`, `description: String`, `isRequired: Bool`, `isSecret: Bool`
- [ ] T019 Implement pure functions in `mcp-inator/Models/RegistryEntry.swift`:
  - `static func deriveCommand(packageType: PackageType, identifier: String) -> (command: String, args: [String])`: npm→("npx",["-y",id]), pypi→("uvx",[id]), oci→("docker",["run",id])
  - `static func displayName(from registryName: String) -> String`: take component after last `/`, strip `-mcp-server`/`-mcp-servers`/`-mcp`/`-server` suffixes, replace `-`/`_` with spaces, title-case
- [ ] T020 Implement `RegistryEntry: Identifiable, Equatable, Codable` struct in `mcp-inator/Models/RegistryEntry.swift`: fields `id`, `displayName`, `description`, `packageType?`, `packageIdentifier?`, `remoteURL?`, `remoteType?`, `remoteHeaders: [RegistryEnvVar]`, `envVars: [RegistryEnvVar]`, `repositoryURL?`, `version`; computed `derivedCommand`, `derivedArgs`, `transportType` (streamableHTTP→.http, sse→.sse, package→.stdio), `isActionable` (has package identifier OR remoteURL); failable `init?(raw: RegistryAPIServerWrapper)` that returns nil when `!isActionable`
- [ ] T021 [P] Write `deriveCommand` unit tests in `mcp-inatorTests/Unit/RegistryEntryTests.swift`: npm produces ("npx",["-y","@foo/bar"]), pypi produces ("uvx",["tool"]), oci produces ("docker",["run","image"])
- [ ] T022 [P] Write `displayName(from:)` unit tests in `mcp-inatorTests/Unit/RegistryEntryTests.swift` with a fixture table: `"io.github.YawLabs/postgres-mcp"` → `"Postgres"`, `"com.foo/home-assistant-mcp-server"` → `"Home Assistant"`, `"ai.smithery/github"` → `"Github"`, `"io.bar/my-cool-server"` → `"My Cool Server"`

### Strip CatalogEntry.swift

- [ ] T023 Edit `mcp-inator/Models/CatalogEntry.swift` to remove `CatalogEntry`, `CatalogEnvVar`, `CatalogMetadata`, and `Catalog` — keep only the `CatalogCategory` enum unchanged (all 7 cases, `var id`, the `Identifiable` conformance); confirm project compiles after removal (CatalogStore.swift still references these types and will be updated in Phase 7, so if the build breaks update those references now by noting the file will be deleted)

**Checkpoint**: All pure functions implemented and unit-tested. `RegistryClient` protocol defined. `RegistryEntry` model complete. Project still compiles (CatalogStore may have errors — acceptable if deletion is pending).

---

## Phase 3: User Story 1 — Browse Servers by Category (Priority: P1) 🎯 MVP

**Goal**: Categories populated from registry cache; shown immediately on subsequent launches; loading states visible on first launch.

**Independent Test**: Delete `~/Library/Application\ Support/mcp-inator/registry-cache.json` if present, launch the app with network, open Catalog — see loading indicators per category then results appear. Relaunch — see results immediately. Verify via `RegistryStoreTests` offline by using a `StubRegistryClient`.

### RegistryStore — Category Cache

- [ ] T024 [US1] Implement `CategoryCacheState: Equatable` enum in `mcp-inator/Services/RegistryStore.swift`: `case uncached`, `case loading`, `case loaded(fetchedAt: Date, entries: [RegistryEntry])`, `case failed(message: String)`
- [ ] T025 [US1] Implement `RegistryCacheFile: Codable` and `CategoryCacheEntry: Codable` in `mcp-inator/Services/RegistryStore.swift`: `version: Int`, `categories: [String: CategoryCacheEntry]` keyed by `CatalogCategory.rawValue`; `CategoryCacheEntry` has `fetchedAt: Date` and `entries: [RegistryEntry]`
- [ ] T026 [US1] Implement `RegistryStore` class skeleton in `mcp-inator/Services/RegistryStore.swift`: `@MainActor final class RegistryStore: ObservableObject`; `@Published private(set) var categoryStates: [CatalogCategory: CategoryCacheState]` initialized to `.uncached` for all categories; `private let client: any RegistryClient`; `private let cacheURL: URL`; `static var defaultCacheURL: URL` (Application Support/mcp-inator/registry-cache.json); `init(client: any RegistryClient = URLSessionRegistryClient(), cacheURL: URL = RegistryStore.defaultCacheURL)`
- [ ] T027 [US1] Implement `loadFromCache()` in `mcp-inator/Services/RegistryStore.swift`: read `cacheURL` if it exists, decode `RegistryCacheFile`, for each category key set `categoryStates[category] = .loaded(fetchedAt:entries:)`; called synchronously from `init` before returning
- [ ] T028 [US1] Implement `saveToCache()` in `mcp-inator/Services/RegistryStore.swift`: encode current loaded categories to `RegistryCacheFile`; write to `cacheURL`; create intermediate directories if needed; silently ignore write errors
- [ ] T029 [US1] Implement category keyword map `static let categoryKeywords: [CatalogCategory: String]` in `mcp-inator/Services/RegistryStore.swift`: `.codeAndDevelopment: "github"`, `.productivity: "notion"`, `.dataAndAnalytics: "postgres"`, `.communication: "slack"`, `.infrastructure: "docker"`, `.aiAndLLMs: "openai"`, `.webAndBrowser: "browser"`
- [ ] T030 [US1] Implement `populateCategories() async` in `mcp-inator/Services/RegistryStore.swift`: for each category with `.uncached` state set `.loading`; use `withTaskGroup` to fetch all categories concurrently (one `client.search(query:keyword, pageSize:100)` per category); on success update state to `.loaded` and call `saveToCache()`; on `URLError` where `error.code == .notConnectedToInternet || error.code == .networkConnectionLost` retain the existing state (do not overwrite `.loaded` with `.failed`; leave `.uncached` as `.uncached`); on other errors set `.failed(message:)`; always runs on `@MainActor` for state updates
- [ ] T031 [US1] Implement `entries(for:) -> [RegistryEntry]`, `categoryState(for:) -> CategoryCacheState`, and `refreshCategory(_ c: CatalogCategory) async` (single-category retry — same offline-safe logic as `populateCategories` but for one category) in `mcp-inator/Services/RegistryStore.swift`

### RegistryStore Tests — Category Cache

- [ ] T032 [P] [US1] Write `RegistryStoreTests` — initial state test in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: create `RegistryStore(client: stub, cacheURL: tempDir)` with no cache file present; assert all 7 category states are `.uncached`
- [ ] T033 [P] [US1] Write `RegistryStoreTests` — cache round-trip in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: define `StubRegistryClient` struct (`var result: Result<[RegistryEntry], Error>`); call `populateCategories()` with stub returning 2 fixture entries for each query; assert all categories transition to `.loaded`; create a second `RegistryStore` pointing at the same tempDir cache file; assert it reads `.loaded` states from disk without calling the network
- [ ] T034 [P] [US1] Write `RegistryStoreTests` — background refresh in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: start with a pre-populated cache file; create store (all categories `.loaded`); call `populateCategories()` with stub returning updated entries; assert categories transition `.loaded` → `.loading` → `.loaded` with new entries

### CatalogView — Category Browsing

- [ ] T035 [US1] Update `mcp-inator/UI/CatalogView.swift` to use `RegistryStore`: replace `@EnvironmentObject var catalogStore: CatalogStore` with `@EnvironmentObject var registryStore: RegistryStore`; when `searchText` is empty, show category picker + per-category content; `entries(for: selectedCategory ?? firstCategory)` drives the list
- [ ] T036 [US1] Add per-category loading state UI in `mcp-inator/UI/CatalogView.swift`: `.uncached`/`.loading` → `ProgressView("Loading…")`; `.loaded(_, let entries)` where entries is empty → "No servers found for this category"; `.loaded` with entries → existing `List` of `CatalogRow`; `.failed` → error message + "Retry" button calling `Task { await registryStore.refreshCategory(selectedCategory) }` (retry single category via `refreshCategory`, not all categories)
- [ ] T037 [US1] Add offline-aware empty state in `mcp-inator/UI/CatalogView.swift` (merged with T049 — complete implementation here): when ALL categories are `.uncached` distinguish two sub-states: (a) if `populateCategories()` has been called but all results were offline errors → show "You're offline — connect to the internet to populate the catalog" with a retry button; (b) if `populateCategories()` has not yet been called → show `ProgressView("Loading…")` for each category slot; never show the offline message before the first populate attempt completes

**Checkpoint**: User Story 1 complete. Categories browse from cache. Loading states visible. Cache persists across launches.

---

## Phase 4: User Story 2 — Search the Full Registry (Priority: P2)

**Goal**: Typing in the search bar triggers a live registry search (debounced 300 ms); results appear within 3 seconds of the user pausing; results filtered to `isLatest: true`.

**Independent Test**: Open the app with network. Type "obsidian" in search bar. Verify live results appear that differ from any cached category. Type a different term — verify results update. Run `RegistryStoreTests` search scenarios with `StubRegistryClient` returning canned data.

### RegistryStore — Search

- [ ] T038 [US2] Implement `SearchState: Equatable` enum in `mcp-inator/Services/RegistryStore.swift`: `case idle`, `case searching`, `case results([RegistryEntry])`, `case localOnly([RegistryEntry])`, `case empty`, `case failed(message: String)`; add `@Published private(set) var searchState: SearchState = .idle` property to `RegistryStore`
- [ ] T039 [US2] Implement `search(query: String) async` in `mcp-inator/Services/RegistryStore.swift`: set `.searching`; call `client.search(query:query, pageSize:100)`; add `guard !Task.isCancelled else { return }` before each state assignment (prevents stale results overwriting newer state); on success with results set `.results(entries)`, empty set `.empty`; on `URLError` where `code == .notConnectedToInternet || code == .networkConnectionLost` collect all entries from `.loaded` category caches, filter by query (displayName or description contains query, case-insensitive), set `.localOnly(filtered)`; on other error set `.failed(message:)`
- [ ] T040 [US2] Implement `cancelSearch()` in `mcp-inator/Services/RegistryStore.swift`: set `searchState = .idle`

### RegistryStore Tests — Search

- [ ] T041 [P] [US2] Write `RegistryStoreTests` — live search in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: call `search(query: "postgres")` with stub returning 3 entries; assert `searchState == .results([...])` with correct count; call `search(query: "nomatchwhatsoever")` with stub returning []; assert `searchState == .empty`
- [ ] T042 [P] [US2] Write `RegistryStoreTests` — search failed in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: call `search(query: "foo")` with stub throwing `URLError(.timedOut)`; assert `searchState == .failed(message:)` (non-offline error)

### CatalogView — Live Search UI

- [ ] T043 [US2] Add Task-based debounce to `mcp-inator/UI/CatalogView.swift`: add `@State private var searchTask: Task<Void, Never>?`; in `.onChange(of: searchText)` cancel `searchTask`; if query empty call `registryStore.cancelSearch()` and return; otherwise assign new Task: `try? await Task.sleep(for: .milliseconds(300))`, guard `!Task.isCancelled`, then `await registryStore.search(query: query)`
- [ ] T044 [US2] Update `mcp-inator/UI/CatalogView.swift` to show `registryStore.searchState` when `!searchText.isEmpty`: `.searching` → `ProgressView("Searching…")`; `.results(let entries)` → `List` of `CatalogRow` (reuse existing); `.empty` → "No results found" empty state; `.failed(let msg)` → error message; `.localOnly(let entries)` → list + banner "Live search unavailable — showing cached results"

**Checkpoint**: User Story 2 complete. Live search active, debounced, state-driven.

---

## Phase 5: User Story 3 — Offline Behavior Tests & Edge Cases (Priority: P3)

**Goal**: Confirm via tests that offline resilience implemented in Phases 3–4 works correctly. No new implementation — the offline logic was built into T030 and T039.

**Independent Test**: After a successful online launch (cache populated), disable network. Relaunch app. Verify all 7 categories display cached entries. Type in search — verify a notice says live search is unavailable and local matches appear.

> **Note**: T045 and T046 are consolidated into T030 and T039 respectively. T049 is consolidated into T037. Phase 5 contains tests and edge-case validation only.

### RegistryStore Tests — Offline

- [ ] T045 [P] [US3] Write `RegistryStoreTests` — offline category fetch in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: pre-populate cache file with data for all categories; create store (all `.loaded`); call `populateCategories()` with stub throwing `URLError(.notConnectedToInternet)`; assert all categories remain `.loaded` (cache not overwritten)
- [ ] T046 [P] [US3] Write `RegistryStoreTests` — offline search in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: pre-populate 2 categories with entries containing "postgres" in display name; call `search(query: "postgres")` with stub throwing `URLError(.notConnectedToInternet)`; assert `searchState == .localOnly(entries)` where `entries` contains only the matching entries
- [ ] T047 [P] [US3] Write `RegistryStoreTests` — partial offline (some categories cached, some not) in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: pre-populate cache for 3 of 7 categories; call `populateCategories()` with stub throwing offline error; assert the 3 cached categories remain `.loaded` and the 4 uncached categories remain `.uncached` (not `.failed`)
- [ ] T048 [P] [US3] Write `RegistryStoreTests` — search cancellation race in `mcp-inatorTests/Unit/RegistryStoreTests.swift`: start a search task, cancel it before the stub result is consumed; assert `searchState` is not overwritten by the cancelled result (remains `.idle` or a newer state)

**Checkpoint**: User Story 3 complete. App fully usable offline with cached data. Clear messaging in all offline states.

---

## Phase 6: User Story 4 — Env Var Suggestions as Hints (Priority: P4)

**Goal**: Env var names from registry data shown in the Add/Edit form clearly marked "Suggested — verify with package docs". Hints are cosmetic only and not persisted.

**Independent Test**: Select any registry server with env vars and tap "Add to Library". Verify each env var field shows a "Suggested" badge and descriptive copy. Edit/clear a value and save — verify the saved config has the user's value, not a special hint marker.

### EnvVar.isHint

- [ ] T050 [US4] Add `var isHint: Bool = false` to `EnvVar` in `mcp-inator/Models/MCPServerConfig.swift`: field NOT added to `CodingKeys` (excluded from DB persistence and agent config file output); update `init(key:value:isSensitive:)` to initialize `isHint = false`; add a second init `init(key:value:isSensitive:isHint:)` for use by `MCPServerConfig.init(from: RegistryEntry)`
- [ ] T051 [P] [US4] Write `EnvVar` persistence test in `mcp-inatorTests/Unit/CatalogEntryTests.swift`: create an `EnvVar` with `isHint = true`; encode to JSON via `JSONEncoder`; decode back; assert decoded `isHint == false` (property reverts to default — confirming it is not in the coding path)

### MCPServerConfig from RegistryEntry

- [ ] T052 [US4] Implement `extension MCPServerConfig { init(from entry: RegistryEntry) }` in `mcp-inator/Models/MCPServerConfig.swift`: for stdio entries use `entry.derivedCommand!` + `entry.derivedArgs!` + map `entry.envVars` → `EnvVar(key:value:"",isSensitive:$0.isSecret,isHint:true)`; for HTTP entries use `entry.remoteURL!` + `entry.transportType` + map `entry.remoteHeaders` → `EnvVar(key:$0.name,value:$0.valueTemplate ?? "",isSensitive:$0.isSecret,isHint:true)` (preserving header value templates as the initial value hint); `serverKey` derived from `entry.displayName` via `MCPServerConfig.generateKey`; check `store.configs.contains { $0.serverKey == derived serverKey }` is NOT the responsibility of init — conflict check happens in the UI (see T069)

### CatalogDetailView — RegistryEntry + Hint Section

- [ ] T053 [US4] Rewrite `mcp-inator/UI/CatalogDetailView.swift` to accept `RegistryEntry` instead of `CatalogEntry`: update struct property to `let entry: RegistryEntry`; update `libraryMatch` to compare `serverKey`; update header (remove `isVerified` badge, show repository link from `entry.repositoryURL`); update transport section to use `entry.derivedCommand`, `entry.derivedArgs`, `entry.remoteURL`, `entry.transportType`; update "Add to Library" to use `MCPServerConfig(from: entry)`
- [ ] T054 [US4] Add env var + remote headers hint sections to `mcp-inator/UI/CatalogDetailView.swift`: for stdio entries when `!entry.envVars.isEmpty` show "Environment Variables" section with a `HintNotice` reading "Variable names are suggested — verify with the package's own documentation before saving"; for HTTP entries when `!entry.remoteHeaders.isEmpty` show "Request Headers" section with the same `HintNotice`; for each `RegistryEnvVar` show `name` (monospaced), `isRequired` badge, `isSecret` lock icon, `description`; if `valueTemplate` is non-nil show it as greyed placeholder text; when both lists are empty show nothing (FR-017)

### AddEditConfigView — Hint Badge

- [ ] T055 [US4] Update `EnvVarRow` in `mcp-inator/UI/AddEditConfigView.swift`: when `envVar.isHint == true`, render a `Text("Suggested")` capsule badge (accent color, caption2 font) between the key and the value field, plus a `.help("Verify this variable name with the package's documentation")` tooltip; hint badge is read-only cosmetic — it does not affect editing, deleting, or saving

**Checkpoint**: User Story 4 complete. Hints visible in both detail and edit views. Not persisted. Users can freely edit or clear hinted values.

---

## Phase 7: Polish & Wiring

**Purpose**: Wire all new types into app entry points, update/delete references to old types, confirm the full test suite passes.

- [ ] T056 [P] Update `mcp-inator/App/mcp_inatorApp.swift`: replace `@StateObject private var catalogStore = CatalogStore()` with `@StateObject private var registryStore = RegistryStore()`; replace `.environmentObject(catalogStore)` with `.environmentObject(registryStore)`; in `onAppear` replace `catalogStore.load()` with `Task { await registryStore.populateCategories() }`
- [ ] T057 [P] Update `mcp-inator/MCP/MCPServer.swift`: replace `let catalogStore = CatalogStore(); catalogStore.load()` with `let registryStore = RegistryStore(); // loads from cache in init`; update `MCPToolHandler(store:catalogStore:)` to `MCPToolHandler(store:registryStore:)`
- [ ] T058 Update `mcp-inator/MCP/MCPTools.swift`: change `MCPToolHandler.init(store:catalogStore:adapterProvider:)` to `init(store:registryStore:adapterProvider:)` with type `RegistryStore`; update `listCatalog()` to iterate `CatalogCategory.allCases`, call `registryStore.entries(for:)` for each, flatten and deduplicate by `entry.id`, map to the existing `CatalogSummary` struct (set `isVerified: false` for all registry entries, derive `command`/`args` from `entry.derivedCommand`/`derivedArgs`)
- [ ] T059 [P] Update `mcp-inatorTests/Unit/MCPToolHandlerTests.swift`: replace all 3 occurrences of `CatalogStore()` with `RegistryStore(client: StubRegistryClient(result: .success([])), cacheURL: tempDir.appendingPathComponent("cache.json"))`; confirm `StubRegistryClient` is accessible (define in the test file or a shared test helper)
- [ ] T060 Delete `mcp-inatorTests/Unit/CatalogStoreTests.swift`: remove the file from disk and from the Xcode test target (all behavior is now covered by `RegistryStoreTests`)
- [ ] T061 Update `mcp-inatorTests/Unit/CatalogEntryTests.swift`: remove tests that reference deleted types (`CatalogEntry`, `CatalogEnvVar`); add or update tests for `MCPServerConfig.init(from: RegistryEntry)`: stdio path sets correct command/args/envVars with `isHint=true`; HTTP path sets correct url/transportType/headers with `isHint=true`; `isSensitive` propagated correctly from `RegistryEnvVar.isSecret`
- [ ] T062 Delete `mcp-inator/Services/CatalogStore.swift` from disk and remove from Xcode app target; delete `mcp-inator/Resources/catalog.json` (or wherever it lives in the Xcode project navigator) and remove from the app target's Copy Bundle Resources phase
- [ ] T063 Update `mcp-inatorTests/Integration/MCPServerTests.swift`: confirm `list_catalog` is still present in the tools list; tool count should remain 7 (no change); if `testToolsList` hard-codes a count, verify it still matches
- [ ] T064 Run `make test` from the repo root and fix any remaining failures; run `make lint` and fix all warnings

**Checkpoint**: Full test suite green. Lint clean. CatalogStore and catalog.json gone. All user stories wired end-to-end.

---

## Phase 8: Gap Coverage (Analysis-Identified Missing Tasks)

**Purpose**: Tasks added from the speckit-analyze pass to close FR coverage gaps and confirmed edge cases.

- [ ] T065 [P] Write end-to-end non-actionable filter test in `mcp-inatorTests/Unit/RegistryClientTests.swift`: decode `registry-response.json` fixture (which contains one non-actionable entry with no packages and no remotes); call `URLSessionRegistryClient`'s transform pipeline (filterLatest → deduplicate → RegistryEntry.init?); assert the non-actionable entry is absent from the final `[RegistryEntry]` array (FR-013 coverage)
- [ ] T066 Write FR-016 end-to-end persistence test in `mcp-inatorTests/Unit/CatalogEntryTests.swift`: create `MCPServerConfig` via `init(from: RegistryEntry)` with one env var (`isHint=true`); mutate the env var value to "user_actual_value"; encode via `JSONEncoder`; decode via `JSONDecoder`; assert the decoded env var has `value == "user_actual_value"` and `isHint == false` (confirms user-entered values persist normally and hint flag does not survive a round-trip)
- [ ] T067 [P] Write nil-coercion test in `mcp-inatorTests/Unit/RegistryEntryTests.swift`: construct a `RegistryAPIEnvVar` with all optional fields set to nil; call `RegistryEntry.init?(raw:)` with a server wrapper containing this env var; assert resulting `RegistryEnvVar` has `description == ""`, `isRequired == false`, `isSecret == false`; separately construct a `RegistryAPIEnvVar` with blank `name` ("  ") and assert it is absent from the resulting entry's `envVars` array
- [ ] T068 [P] Write precedence test in `mcp-inatorTests/Unit/RegistryEntryTests.swift`: construct a `RegistryAPIServerWrapper` with both a valid npm package AND a streamable-http remote; assert `RegistryEntry.init?(raw:)` produces `transportType == .stdio` and `packageType == .npm` and `remoteURL == nil`
- [ ] T069 [US4] Implement FR-018 duplicate serverKey guard in `mcp-inator/UI/CatalogDetailView.swift`: `libraryMatch` already checks `store.configs.contains { $0.serverKey == entry.serverKey }`; when `libraryMatch != nil` the "Add to Library" button is replaced by "Edit in Library" — confirm this logic correctly uses the derived `serverKey` from `MCPServerConfig.generateKey(from: entry.displayName)` to detect conflicts; add an "Already in your library" visual indicator in the detail header when `libraryMatch != nil`
- [ ] T070 [P] [US4] Write FR-018 test in `mcp-inatorTests/Unit/CatalogEntryTests.swift`: seed a `ConfigStore` with an `MCPServerConfig` whose `serverKey` matches `MCPServerConfig.generateKey(from: registryEntry.displayName)`; assert that the derived serverKey matches the existing entry's key (confirming the collision detection will work)

**Checkpoint**: All FR-identified gaps closed. Analysis findings F01–F04, F16, F19 resolved.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phase 3 (US1)**: Depends on Phase 2 — can start immediately after
- **Phase 4 (US2)**: Depends on Phase 2 — can start in parallel with Phase 3 after Phase 2 completes
- **Phase 5 (US3 tests)**: Depends on Phase 3 and Phase 4 — tests-only, verifies offline logic built in T030/T039
- **Phase 6 (US4)**: Depends on Phase 2 — can start in parallel with Phases 3–5
- **Phase 7 (Polish)**: Depends on Phases 3–6
- **Phase 8 (Gap Coverage)**: Can run in parallel with Phase 7

### User Story Dependencies

- **US1 (P1)**: Start after Phase 2 — no dependency on US2–US4
- **US2 (P2)**: Start after Phase 2 — adds `search()` to `RegistryStore` which US3 also hardens
- **US3 (P3)**: Hardens US1 and US2 implementations — start after US2
- **US4 (P4)**: Depends only on Phase 2 (`RegistryEntry` model) — can be developed in parallel with US1–US3

### Within Each Phase

- Phase 2: raw API structs → transformation functions → `RegistryEntry` → tests (some in parallel)
- Phase 3: `RegistryStore` core → category fetch → tests → `CatalogView` UI
- Phase 4: `SearchState` → `search()` → tests → search UI
- Phase 5: offline tests only — implementation is in T030 and T039

---

## Parallel Execution Examples

### Phase 2 (after T010–T011)

```
T012 filterLatest/deduplicate tests   ←── parallel
T016 PackageType enum                 ←── parallel
T017 RemoteTransportType enum         ←── parallel
T018 RegistryEnvVar struct            ←── parallel
```

### Phase 3 (after T026 skeleton)

```
T027 category keyword map             ←── parallel
T032 RegistryStoreTests initial state ←── parallel
T033 RegistryStoreTests cache round-trip ←── parallel after T030 complete
```

### Phase 6 (after T050)

```
T051 isHint persistence test          ←── parallel
T052 MCPServerConfig.init(from:)      ←── sequential (needs T050)
T053 CatalogDetailView rewrite        ←── parallel with T052
```

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Phase 1: Setup
2. Phase 2: Foundational — pure functions + RegistryClient + RegistryEntry + tests
3. Phase 3: RegistryStore category cache + CatalogView category UI
4. **STOP AND VALIDATE**: Delete cache file, launch app, verify categories populate. Relaunch, verify immediate cache. Run test suite.
5. Phase 7 (partial): Wire mcp_inatorApp.swift, MCPServer.swift, MCPTools.swift only

### Full Delivery

Complete all phases in order (with parallel opportunities per story). Each phase checkpoint is a working, testable state.

---

## Notes

- [P] tasks operate on different files with no blocked dependencies
- `StubRegistryClient` should be defined in a shared test helper or inline in `RegistryStoreTests` — whichever keeps it reusable across test classes
- When deleting Xcode targets, use Xcode's "Delete" (remove reference + trash) not just "Remove Reference"
- `CatalogCategory.rawValue` strings are the cache file keys — do not rename the enum cases without migrating the cache format
- The `list_catalog` MCP tool output shape is unchanged — downstream AI agents need not be notified
