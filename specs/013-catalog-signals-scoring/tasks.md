# Tasks: Catalog Signals & Scoring

**Input**: Design documents from `specs/013-catalog-signals-scoring/`

**Feature**: Extend the mcp-inator catalog with popularity and quality signals for confident server discovery as the catalog grows to 80–100+ entries.

**Two-repo scope**: Pipeline work in `mcp-catalog` repo; Swift model + UI work in `mcp-inator` repo.

**Tests**: Included per plan.md (E1–E4 unit tests cover models, scoring, sort logic, and category backward compat).

---

## Phase 1: Setup

**Purpose**: Feature branch already active; no new project initialization needed.

- [ ] T001 Verify feature branch `013-catalog-signals-scoring` is checked out and up to date with main

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema and model-layer changes that all three user stories depend on. A1 must be stable before D1. B1–B3 must be complete before B4, B5, and any UI work.

**⚠️ CRITICAL**: No user story implementation can begin until this phase is complete.

- [ ] T002 [P] Update `servers.json` in the `mcp-catalog` repo — rename `isFirstParty` → `isOfficial` (set correct values per data-model.md table), add `relatedApp` (GitHub Desktop, Slack, Notion, Linear, Google Drive, Docker; null for others), add `editorialRank: null` to all 18 existing entries, update `category` values to new slug taxonomy (`developer-tools`, `search-web`, `databases`, `productivity`, `ai-memory`, `infrastructure`), remove `isVerified`, add `moov-docs` entry (editorialRank: 1, category: finance, command: npx, args: ["-y", "mcp-remote", "https://docs.moov.io/mcp"]), bump `schemaVersion` to `3` (A1)
- [ ] T003 [P] Update `CatalogCategory` enum in `mcp-inator/Models/CatalogEntry.swift` — change raw values to slug strings (`"developer-tools"`, `"search-web"`, `"databases"`, `"productivity"`, `"ai-memory"`, `"infrastructure"`, `"finance"`), add `label: String` computed property, add custom `init(from:)` decoder that accepts both old display-string values (`"Code & Development"`, `"Web & Browser"`, `"Data & Analytics"`, `"Productivity, Communication"`, `"AI & LLMs"`) and new slug values, add `finance` case (B2)
- [ ] T004 [P] Update `CatalogEntry` struct in `mcp-inator/Models/CatalogEntry.swift` — add `isOfficial: Bool`, `relatedApp: String?`, `editorialRank: Int?`; remove `isVerified` and `isFirstParty`; add custom `init(from decoder:)` that sets `isOfficial = isOfficial ?? isFirstParty ?? false` for backward compat with cached entries; update `CodingKeys` enum (B1)
- [ ] T005 [P] Update `ServerMetrics` struct in `mcp-inator/Models/CatalogEntry.swift` — append 8 new optional fields: `githubStarsIsShared: Bool?`, `githubCommits90d: Int?`, `npmWeeklyDownloads: Int?`, `pypiMonthlyDownloads: Int?`, `dockerTotalPulls: Int?`, `smitheryUseCount: Int?`, `baseScore: Double?`, `signalsRefreshedAt: String?`; use `decodeIfPresent` for all new fields (B3)

**Checkpoint**: Schema stable, data model layer complete. US1, US2, US3 implementation can begin.

---

## Phase 3: User Story 1 — Browse catalog with confidence signals (Priority: P1) 🎯 MVP

**Goal**: Each catalog row shows trust and popularity signals (Official badge, install count, stars with "repo" qualifier, stale warning); default sort order puts most useful servers first with editorial-pinned entries at the top.

**Independent Test**: Load a hand-crafted `catalog.json` with full, partial, and null signal data; verify list renders correctly with correct badges and sort order; verify null-signal entries render without placeholders or errors.

### Tests for User Story 1

- [ ] T006 [P] [US1] Create `mcp-inatorTests/CatalogCategoryTests.swift` — test old display-string values decode to correct enum cases (`"Code & Development"` → `.developerTools`, `"Web & Browser"` → `.searchWeb`, `"AI & LLMs"` → `.aiMemory`, etc.); test new slug values decode correctly (E4)
- [ ] T007 [P] [US1] Create `mcp-inatorTests/CatalogEntryTests.swift` — test new fields decode correctly; test `isOfficial` falls back to old `isFirstParty` key; test `isVerified` absence causes no error; test all 8 signal fields decode as nil when absent (E1)
- [ ] T008 [P] [US1] Create `mcp-inatorTests/CatalogViewModelTests.swift` — test `displayScore` equals `baseScore` when no related app matches; test `isStale` is true when `lastCommitDate` is >180 days ago, false at 179 days, false when date is nil; test `installCountLabel` formats npm weekly as "289k/wk" and docker as "116k pulls"; test `starsIsShared` reflects `githubStarsIsShared` flag (E2 partial)
- [ ] T009 [P] [US1] Create `mcp-inatorTests/CatalogStoreTests.swift` — test entries with `editorialRank` sort before unranked entries; test two entries with the same `editorialRank` sort by `displayScore` descending; test `sortedEntries` excludes `alternativeTo` entries; test `discoverEntries` excludes entries already in the library; test `discoverEntries` excludes editorial-ranked entries in the primary path; test `discoverEntries` returns at most 5 entries sorted by `displayScore`; test fallback: when all non-editorial entries are in library, `discoverEntries` falls back to editorial entries not in library rather than returning empty (E3 partial)

### Implementation for User Story 1

- [ ] T010 [US1] Add computed properties to `CatalogViewModel` in `mcp-inator/Models/CatalogEntry.swift` — `installedApps: Set<String>` stored property (injected at init), `displayScore: Double` (baseScore + appBoost where appBoost = 3.0 if relatedApp lowercased is in installedApps), `isStale: Bool` (lastCommitDate > 180 days), `installCount: Int?` (npm weekly ?? docker pulls), `installCountLabel: String?` (formatted "289k/wk" or "116k pulls"), `starsIsShared: Bool`, `isOfficial: Bool` (B4)
- [ ] T011 [US1] Update `CatalogStore` in `mcp-inator/Services/CatalogStore.swift` — add `sortedEntries: [CatalogViewModel]` (editorial pins first by rank, then displayScore descending, excludes alternativeTo entries), add `discoverEntries(libraryKeys: Set<String>) -> [CatalogViewModel]` (primary: non-editorial entries not in library; fallback when primary is empty: include editorial entries not in library; always up to 5, never empty as long as any entry is outside the library), remove `trendingEntries`, remove `entriesByCategory` (unused after C3 switches to flat list) (B5 partial)
- [ ] T012 [P] [US1] Rename `FirstPartyBadge` → `OfficialBadge` in `mcp-inator/UI/CatalogView.swift` — update struct name, update all call sites, wire to `entry.isOfficial` instead of `entry.isFirstParty` (C2)
- [ ] T013 [US1] Replace existing stars + age `HStack` in `CatalogRow` with signal row in `mcp-inator/UI/CatalogView.swift` — show `OfficialBadge` if `entry.isOfficial`, `installCountLabel` with download icon, stars with `" repo"` suffix if `starsIsShared`, amber stale warning if `vm.isStale` (C1)
- [ ] T014 [US1] Update browse layout in `CatalogView` in `mcp-inator/UI/CatalogView.swift` — when no category filter active: replace `trendingSection` with a **Featured** section (entries with non-null `editorialRank`, always shown) and a **Discover** section (`discoverEntries` result, always shown as long as any entries are outside the user's library — shows up to 5, shows fewer if that's all that's available, falls back to editorial entries if needed), replace `entriesByCategory` grouping with flat `sortedEntries` list below the two sections; when category filter active: show only flat filtered `sortedEntries` list (no Featured/Discover sections) (C3)
- [ ] T015 [US1] Update search in `CatalogView` in `mcp-inator/UI/CatalogView.swift` — search against `sortedEntries` (flat list, score-ordered), extend match to include `category.label` in addition to name/description/curatorNote, results sorted by `displayScore` descending (C4)
- [ ] T016 [P] [US1] Update `RegistryStore.categoryKeywords` map in `mcp-inator/Services/RegistryStore.swift` to use new slug keys (`"developer-tools"`, `"search-web"`, `"databases"`, `"productivity"`, `"ai-memory"`, `"infrastructure"`, `"finance"`) (C5)
- [ ] T017 [US1] Update bundled `catalog/catalog.json` in `mcp-inator` — apply all A1 changes (rename `isFirstParty` → `isOfficial`, add `relatedApp`/`editorialRank`, update category slugs, remove `isVerified`), add `moov-docs` entry, add null stub signal fields to all entries (`npmWeeklyDownloads: null`, `pypiMonthlyDownloads: null`, `dockerTotalPulls: null`, `smitheryUseCount: null`, `githubStarsIsShared: null`, `githubCommits90d: null`, `baseScore: null`, `signalsRefreshedAt: null`), bump `schemaVersion` to `3`; note: null stubs will be replaced with real data by T029 after enrich.py is written (D1)

**Checkpoint**: US1 fully functional. Build and run; verify catalog loads, moov-docs appears first in Featured section, Discover section shows top-5 uninstalled servers, signal row renders for entries with data and cleanly for null-signal entries, search works across flat list and category labels.

---

## Phase 4: User Story 2 — Personalized relevance for installed apps (Priority: P2)

**Goal**: App scans `/Applications` and `~/Applications` at startup; MCP servers whose `relatedApp` is detected get a +3.0 displayScore boost, rising in sort order without any user configuration.

**Independent Test**: Initialize `CatalogStore` with a mock `installedApps` set containing `"notion"`; verify Notion entry's `displayScore` = `baseScore + 3.0` and its sort position reflects the boost; verify Linear entry (not installed) has no boost.

### Tests for User Story 2

- [ ] T018 [P] [US2] Extend `CatalogViewModelTests` in `mcp-inatorTests/CatalogViewModelTests.swift` — test `displayScore = baseScore + 3.0` when matching app is in `installedApps`; test `displayScore = baseScore` when app name not in set; test no boost when `relatedApp` is nil; test app name match is case-insensitive (E2 complete)
- [ ] T019 [P] [US2] Extend `CatalogStoreTests` in `mcp-inatorTests/CatalogStoreTests.swift` — test `scanInstalledApps()` returns lowercase names without `.app` suffix; test scan handles an empty or missing directory gracefully; test scan result is injected into each `CatalogViewModel` (E3 complete)

### Implementation for User Story 2

- [ ] T020 [US2] Add `installedApps: Set<String>` property and `scanInstalledApps()` static helper to `CatalogStore` in `mcp-inator/Services/CatalogStore.swift` — scan `/Applications` and `~/Applications` for `.app` bundles, lowercased names without suffix; call at `init`; pass result into each `CatalogViewModel` during `fetchIfNeeded` (B5 complete)

**Checkpoint**: US2 functional. With Notion.app or GitHub Desktop installed, verify the matching server appears higher in the sorted list than its raw baseScore alone would place it.

---

## Phase 5: User Story 3 — Signal data stays fresh via automated pipeline (Priority: P3)

**Goal**: A weekly CI job in `mcp-catalog` fetches npm, PyPI, Docker, Smithery, and GitHub signals for every server, computes baseScore, and writes `stats.json` — without touching editorial fields in `servers.json`.

**Independent Test**: Run `uv run scripts/enrich.py` manually against local `mcp-catalog` files; verify `stats.json` has updated signal fields and `baseScore`; verify `servers.json` editorial fields (`isOfficial`, `relatedApp`, `editorialRank`, `category`) are unchanged; verify a simulated API failure writes `null` for that field rather than aborting.

### Tests for User Story 3

- [ ] T021 [P] [US3] Create `mcp-catalog/scripts/tests/test_enrich.py` — test scoring formula produces correct `baseScore` for known inputs (npm + docker + Smithery + isOfficial + recency bonus); test Smithery cap: `smitheryUseCount` = 1,600,000 scores same as 100,000; test recency bonus: +2 for <90 days, 0 for <1 year, −2 for >1 year; test `githubStarsIsShared` is `true` for all entries sharing the same `repositoryURL`, `false` for unique repos (A4)

### Implementation for User Story 3

- [ ] T022 [US3] Write `mcp-catalog/scripts/enrich.py` — PEP 723 inline `# dependencies = ["requests"]` for `uv run`; reads `servers.json` for entry list and `stats.json` for existing data; for each entry fetches npm weekly downloads, PyPI monthly downloads, Docker Hub total pulls, Smithery useCount, GitHub commits-by-path (90-day window, path derived from `documentationURL` for mono-repo entries); detects `githubStarsIsShared` (multiple entries sharing same `repositoryURL`); computes `baseScore` using log-scale formula (cap Smithery at 100k); writes updated `stats.json` preserving all existing fields non-destructively; handles each API failure gracefully (null field, continue); runnable standalone via `uv run scripts/enrich.py` (A2)
- [ ] T023 [US3] Add `mcp-catalog/.github/workflows/refresh.yml` — weekly cron trigger (Sunday 04:00 UTC), steps: checkout repo → run `python scripts/refresh.py` → run `uv run scripts/enrich.py` → commit updated `stats.json` if changed using `GITHUB_TOKEN` (available by default in Actions) (A3)

**Checkpoint**: US3 functional. Run `uv run scripts/enrich.py` against the live `mcp-catalog` repo; inspect `stats.json` output for signal fields and `baseScore`; confirm `servers.json` editorial fields are unmodified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T024 [P] Delete `mcp-inator/scripts/score_probe.py` — research artifact superseded by `mcp-catalog/scripts/enrich.py`; manual signal inspection now uses `uv run scripts/enrich.py` in the mcp-catalog repo (D2)
- [ ] T029 Run `uv run scripts/enrich.py` in the `mcp-catalog` repo to populate real signal data, then copy the resulting signal field values from `stats.json` into the bundled `mcp-inator/catalog/catalog.json` so the offline fallback ships with actual scores rather than null stubs (depends on T022)
- [ ] T025 Run `make lint` in `mcp-inator` and fix all SwiftLint warnings before PR
- [ ] T026 Run `make cover` in `mcp-inator` and verify test coverage meets threshold
- [ ] T027 Bump patch version in `mcp-inator/VERSION` (e.g. `0.4.4` → `0.4.5`)
- [ ] T028 Update `mcp-inator/RELEASE_NOTES.md` with feature summary: catalog signal row, score-based sort, Featured/Discover sections, installed-app boost, moov-docs entry

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — T002–T005 are all parallelizable within the phase
- **Phase 3 (US1)**: Depends on T003, T004, T005 (B1–B3 models complete); T002 (A1) must be done before T017 (D1)
- **Phase 4 (US2)**: Depends on T010 (B4 CatalogViewModel with installedApps parameter)
- **Phase 5 (US3)**: Depends on T002 (A1 servers.json stable as input to enrich.py); independent of Swift work
- **Phase 6 (Polish)**: Depends on all prior phases complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational (Phase 2) — no other story dependencies
- **US2 (P2)**: Depends on US1 T010 (CatalogViewModel with installedApps parameter in place)
- **US3 (P3)**: Depends on T002 (A1 schema stable) — otherwise independent of US1/US2

### Parallel Opportunities

Within Phase 2: T002, T003, T004, T005 can all run in parallel (different files, different repos).

Within Phase 3:
- Tests T006–T009 can run in parallel (different test files)
- T003/T004/T005 completion unblocks T010 and T011 in parallel
- T012 (OfficialBadge rename) can run in parallel with T010/T011
- T013, T014, T015 are sequential (CatalogRow → browse layout → search, all in CatalogView.swift)
- T016 and T017 can run in parallel with UI tasks (different files)

Within Phase 5: T021 (tests) can be written in parallel with T022 (enrich.py) and T023 (CI workflow).

---

## Parallel Example: Phase 2 (Foundational)

```
# All four foundational tasks can start simultaneously:
Task T002: Update servers.json (mcp-catalog repo)
Task T003: Update CatalogCategory enum (mcp-inator/Models/CatalogEntry.swift)
Task T004: Update CatalogEntry struct (mcp-inator/Models/CatalogEntry.swift) ← same file as T003, coordinate
Task T005: Update ServerMetrics struct (mcp-inator/Models/CatalogEntry.swift) ← same file, coordinate
```

Note: T003, T004, T005 are all in `CatalogEntry.swift` — they can be done in a single editing pass.

## Parallel Example: Phase 3 US1 Tests

```
# All four test files are independent:
Task T006: CatalogCategoryTests.swift
Task T007: CatalogEntryTests.swift
Task T008: CatalogViewModelTests.swift
Task T009: CatalogStoreTests.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T002–T005)
2. Complete Phase 3: US1 (T006–T017)
3. **STOP and VALIDATE**: Build and run app; verify catalog signal row, sort order, Featured/Discover sections, and search all work end-to-end
4. Proceed to US2 and US3

### Incremental Delivery

1. Phase 2 → Foundation ready
2. Phase 3 (US1) → Signal display + smart sort → Demo MVP
3. Phase 4 (US2) → Installed-app personalization → Demo with Notion boost
4. Phase 5 (US3) → Automated pipeline in mcp-catalog → Signal data stays fresh weekly
5. Phase 6 → Polish, lint, coverage, version bump → Ready for PR

---

## Summary

| Phase | Tasks | Story | Key Deliverable |
|-------|-------|-------|-----------------|
| 1 Setup | T001 | — | Branch confirmed |
| 2 Foundational | T002–T005 | — | Schema v3 + Swift models |
| 3 US1 (P1) | T006–T017 | US1 | Signal row + score-based sort |
| 4 US2 (P2) | T018–T020 | US2 | Installed-app boost |
| 5 US3 (P3) | T021–T023 | US3 | Weekly signal pipeline |
| 6 Polish | T024–T029 | — | Lint, coverage, real signal data in bundled catalog |

**Total**: 29 tasks | **Parallelizable**: 14 | **Sequential**: 15

**Suggested MVP**: Complete Phases 1–3 (T001–T017) for a shippable catalog-signals feature without the pipeline automation.

**Note on T029**: T029 (populate bundled catalog with real signal data) depends on T022 (enrich.py) being complete. It can run in Phase 6 after US3 work is done.
