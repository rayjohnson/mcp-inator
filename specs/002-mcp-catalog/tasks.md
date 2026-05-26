# Tasks: MCP Server Catalog

**Branch**: `002-mcp-catalog` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

**Input**: Design documents from `specs/002-mcp-catalog/`

**Note on US3**: User Story 3 (remote catalog refresh) is deferred to post-v1 per plan decision. FR-009, FR-010, FR-011 are out of scope. No tasks generated for US3.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no incomplete dependencies)
- **[Story]**: Which user story this task belongs to
- Exact file paths included in all descriptions

---

## Phase 1: Setup

**Purpose**: Tooling and project scaffolding before any feature work begins.

- [X] T001 Create `Makefile` at repo root with `build`, `test`, `lint`, `run`, `sync-catalog`, `clean` targets (see plan.md Phase A)
- [X] T002 [P] Create `mcp-inator/Services/` directory and add `Services` group to `mcp-inator.xcodeproj/project.pbxproj` alongside the existing `Models`, `UI`, `Store` groups
- [X] T003 [P] Create `catalog/` directory at repo root and add empty `catalog/catalog.json` placeholder (will be populated in Phase 2)

**Checkpoint**: `make lint` runs cleanly; project structure matches plan.md source layout.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Data model, catalog data, and core store — all user stories depend on this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Create `mcp-inator/Models/CatalogEntry.swift` defining: `CatalogCategory` enum (7 cases with raw string values from data-model.md), `CatalogEnvVar` struct, `CatalogEntry` struct, `CatalogMetadata` struct, `Catalog` struct — all `Codable` and conforming to the schema in `contracts/catalog-json-schema.md`
- [X] T005 [P] Add `MCPServerConfig.init(from entry: CatalogEntry)` convenience initialiser to `mcp-inator/Models/MCPServerConfig.swift` using the field mapping table in `data-model.md`
- [X] T006 Populate `catalog/catalog.json` at repo root with ≥15 entries across ≥4 categories, conforming to `contracts/catalog-json-schema.md`; required entries: GitHub, Slack, Linear, filesystem, Brave Search, PostgreSQL, SQLite, Puppeteer, fetch, memory, home-assistant, Notion, Google Drive, Docker, plus one AI/LLM provider
- [X] T007 Run `make sync-catalog` to copy `catalog/catalog.json` → `mcp-inator/Resources/catalog.json`; wire `catalog.json` into Xcode Copy Bundle Resources build phase by editing `mcp-inator.xcodeproj/project.pbxproj` (same pattern used for `Inator.png` in prior work)
- [X] T008 Create `mcp-inator/Services/CatalogStore.swift` as `@MainActor final class CatalogStore: ObservableObject` with: `@Published var entries: [CatalogEntry]`, `func load()` that decodes `catalog.json` from the app bundle (graceful empty-state on schema version mismatch — no crash)

**Checkpoint**: App compiles. `CatalogStore().load()` returns entries from the bundle JSON. `MCPServerConfig(from:)` produces a correct pre-filled config.

---

## Phase 3: User Story 1 — Browse Catalog and Add a Server (Priority: P1) 🎯 MVP

**Goal**: A user can open the Catalog tab, browse all entries, tap one to see its details, and tap "Add to Library" to open a pre-filled Add/Edit form. "Already in library" entries show a visual indicator and offer "Edit in Library" instead.

**Independent Test**: Open mcp-inator with an empty library → open Catalog tab → locate any entry → tap to open detail view → confirm name, description, command/URL, env vars, and docs link are shown → tap "Add to Library" → confirm `AddEditConfigView` opens with `command`, `args`, and env var names pre-filled → fill required fields and save → entry appears in library. Verify no agent config files were modified.

- [X] T009 [P] [US1] Add `init(prefill: MCPServerConfig)` to `mcp-inator/UI/AddEditConfigView.swift` that pre-populates all `@State` fields identically to `init(existing:)` but sets `existing = nil` so that saving calls `store.insert()` rather than `store.update()`
- [X] T010 [P] [US1] Create `mcp-inator/UI/CatalogDetailView.swift` as a sheet view showing: entry `displayName`, `shortDescription`, `category` badge, transport details (command + args for stdio; URL for HTTP), env vars list (each row: name, description, required badge), `documentationURL` link, and `repositoryURL` link (if present)
- [X] T011 [US1] Add "Add to Library" / "Edit in Library" button logic to `mcp-inator/UI/CatalogDetailView.swift`: check `store.configs.contains { $0.serverKey == entry.serverKey }`; if false show "Add to Library" → navigate to `AddEditConfigView(prefill: MCPServerConfig(from: entry))`; if true show "Edit in Library" → navigate to `AddEditConfigView(existing: matchingConfig)`
- [X] T012 [US1] Create `mcp-inator/UI/CatalogView.swift` with a `List` of all `catalogStore.entries`; each row shows entry `displayName`, `category` badge, `shortDescription` truncated to 2 lines, and an "In Library" indicator dot when `serverKey` matches an existing `store.configs` entry; tapping a row presents `CatalogDetailView` as a sheet
- [X] T013 [US1] Add Catalog as a third tab in `mcp-inator/UI/MenuBarView.swift` (after Library and Agents) with `Label("Catalog", systemImage: "square.grid.2x2")`; pass `CatalogStore` via `.environmentObject`
- [X] T014 [US1] Instantiate `CatalogStore` as `@StateObject private var catalogStore = CatalogStore()` in `mcp-inator/App/mcp_inatorApp.swift`; call `catalogStore.load()` in `init()`; inject via `.environmentObject(catalogStore)` on the `MenuBarExtra` content

**Checkpoint**: Catalog tab is visible and populated. Tapping any entry opens the detail sheet. "Add to Library" opens a pre-filled form. Saving the form adds the config to the library. The entry then shows "In Library" / "Edit in Library" on next view.

---

## Phase 4: User Story 2 — Search and Filter the Catalog (Priority: P1)

**Goal**: A user can type in a search field to filter entries by name or description in real time, and select a category to show only entries in that category.

**Independent Test**: Open Catalog tab with ≥10 entries across ≥3 categories → type a server name in the search field → verify only matching entries appear after each keystroke with no perceptible lag → clear search → select a category from the filter → verify only entries in that category are shown and the visible count updates → select "All" → verify full list returns → type a query that matches nothing → verify empty state message appears with a "Clear" action.

- [X] T015 [P] [US2] Add `func filtered(search: String, category: CatalogCategory?) -> [CatalogEntry]` to `mcp-inator/Services/CatalogStore.swift`; filter uses `localizedCaseInsensitiveContains` on `displayName` and `shortDescription`; `category == nil` means "All"
- [X] T016 [P] [US2] Add `@State private var searchText: String` and a `searchable(text:)` modifier (or manual `TextField`) to `mcp-inator/UI/CatalogView.swift` wired to `catalogStore.filtered(search:category:)`
- [X] T017 [US2] Add category filter to `mcp-inator/UI/CatalogView.swift`: `@State private var selectedCategory: CatalogCategory?`; render as a horizontally scrolling row of filter chips or a `Picker` showing "All" plus all 7 `CatalogCategory` cases; selection updates the filtered list
- [X] T018 [US2] Add empty state view to `mcp-inator/UI/CatalogView.swift` shown when `filtered(search:category:)` returns an empty array; message explains no results matched; includes a "Clear Search" button that resets `searchText` and `selectedCategory`

**Checkpoint**: Typing in search filters the list in real time. Selecting a category filters by category. Combined search + category filter works. Empty state appears and clears correctly.

---

## Phase 5: Tests

**Purpose**: Unit tests for data layer logic. No UI tests (manual verification per story checkpoints above).

- [X] T019 [P] Create `mcp-inatorTests/Unit/CatalogStoreTests.swift`: test `load()` returns entries from a fixture JSON; test `filtered(search:category:)` with matching name, matching description, non-matching query, nil category, specific category; test schema version mismatch in fixture returns empty entries without throwing
- [X] T020 [P] Create `mcp-inatorTests/Unit/CatalogEntryTests.swift`: test `MCPServerConfig.init(from: CatalogEntry)` maps all fields correctly for a stdio entry and an HTTP entry; test `isSensitive` propagation; test `defaultValue` used when present and empty string used when nil

**Checkpoint**: `make test` passes with all new test cases green.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T021 Verify `CatalogCategory` badge styling in `CatalogView` and `CatalogDetailView` is visually consistent with existing `AgentStateBadge` and transport type badge patterns in `AgentListView.swift`
- [X] T022 [P] Add `.help()` tooltips to "Add to Library" and "Edit in Library" buttons in `mcp-inator/UI/CatalogDetailView.swift`
- [ ] T023 [P] Update `specs/002-mcp-catalog/quickstart.md` to reflect any implementation details that diverged from the original plan
- [X] T024 Run `make sync-catalog` and `make build` end-to-end; verify bundle contains `catalog.json` and all ≥15 entries appear in the Catalog tab; run through the independent test scenarios for US1 and US2 from this file

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately; T002 and T003 are parallel
- **Phase 2 (Foundational)**: Requires Phase 1 — blocks all user story phases
  - T004 (models) must complete before T005, T008
  - T006 (catalog data) must complete before T007 (sync)
  - T004 + T007 must complete before T008 (CatalogStore needs model + file)
- **Phase 3 (US1)**: Requires Phase 2 complete
  - T009 and T010 are parallel (different files)
  - T011 requires T010 (adds button logic to detail view)
  - T012 requires T009, T011 (list uses detail sheet and prefill init)
  - T013 requires T012 (tab needs CatalogView)
  - T014 requires T013 (app needs tab wired before store injection)
- **Phase 4 (US2)**: Requires Phase 3 complete (US2 builds on CatalogView created in US1)
  - T015 and T016 are parallel (store method vs. UI binding)
  - T017 requires T015, T016
  - T018 requires T017
- **Phase 5 (Tests)**: T019 and T020 are parallel; can run after Phase 2
- **Phase 6 (Polish)**: Requires Phases 3, 4, 5 complete

### Parallel Opportunities

```
Phase 1:  T002 ║ T003
Phase 2:  T004 → T005 (parallel with T006)
          T006 → T007 → T008
Phase 3:  T009 ║ T010 → T011 → T012 → T013 → T014
Phase 4:  T015 ║ T016 → T017 → T018
Phase 5:  T019 ║ T020
Phase 6:  T022 ║ T023 (after T021)
```

---

## Implementation Strategy

### MVP (User Stories 1 + 2 — both P1)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational ← **blocks everything**
3. Complete Phase 3: US1 — catalog browse + add
4. Validate US1 independently using its Independent Test
5. Complete Phase 4: US2 — search + filter
6. Validate US2 independently using its Independent Test
7. Complete Phase 5: Tests (`make test` green)
8. Complete Phase 6: Polish

### Post-v1 (deferred)

- US3 / FR-009/010/011: Remote catalog refresh via `raw.githubusercontent.com` — deferred pending repo hosting decision. `CatalogStore` is already structured to support adding `refresh() async` without architectural changes.

---

## Notes

- `[P]` = different files, no incomplete dependencies — safe to implement in parallel
- No GRDB migrations required for this feature (catalog is JSON-only)
- `make sync-catalog` must be run any time `catalog/catalog.json` is edited before building
- `make build` automatically runs `sync-catalog` first
- US3 tasks are intentionally absent — see plan.md for deferral rationale
