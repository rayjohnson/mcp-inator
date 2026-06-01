# Implementation Plan: Catalog Signals & Scoring

**Branch**: `013-catalog-signals-scoring` | **Date**: 2026-06-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-catalog-signals-scoring/spec.md`

## Summary

Extend the mcp-inator catalog with popularity and quality signals so users can discover and evaluate MCP servers as the catalog grows to 80–100+ entries. The work spans two repos: `mcp-catalog` gets a new `enrich.py` pipeline script and schema extensions; `mcp-inator` gets updated Swift models, sort logic, installed-app detection, and revised list-row UI. The existing two-file architecture (`servers.json` + `stats.json`) maps directly to the editorial/signals split in the spec — no structural change needed, only additive field additions.

## Technical Context

**Language/Version**: Swift 5.9 (mcp-inator), Python 3.11+ (mcp-catalog pipeline)

**Primary Dependencies**: SwiftUI, Combine, Foundation (mcp-inator); `requests` via uv PEP 723 inline deps (pipeline)

**Storage**: `mcp-catalog/servers.json` (editorial), `mcp-catalog/stats.json` (signals + computed score), bundled `catalog/catalog.json` in app as offline fallback

**Testing**: XCTest (mcp-inator); pytest (mcp-catalog/scripts/tests)

**Target Platform**: macOS 14+ menu bar app

**Project Type**: macOS desktop app (SwiftUI + AppKit hybrid) + standalone Python pipeline script

**Performance Goals**: Catalog renders within existing load budget; installed-app scan completes synchronously at startup (<10ms for typical /Applications size)

**Constraints**: Pipeline must not overwrite editorial fields in servers.json; Swift decoder must handle both old and new category raw values for backward compat with cached entries; Smithery useCount capped at 100k in scoring to guard against anomalies

**Scale/Scope**: 18 → 80–100 catalog entries; pipeline touches ~6 external APIs per entry

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | PASS | Pure SwiftUI/AppKit; installed-app scan uses FileManager, no web tech |
| II. Single Source of Truth | PASS | `servers.json` remains the canonical editorial record; `stats.json` the canonical signal record |
| III. Non-Destructive Configuration | PASS | No changes to config storage or adapter logic |
| IV. Config Portability | PASS | No changes to adapter or library model |
| V. Simplicity & Discoverability | PASS | Signals improve discoverability; no new UI modes or settings |

No complexity violations. Complexity Tracking table not required.

## Project Structure

### Documentation (this feature)

```text
specs/013-catalog-signals-scoring/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### mcp-catalog changes

```text
mcp-catalog/
├── servers.json                    # MODIFY — add isOfficial, relatedApp, editorialRank; rename isFirstParty; update categories; bump schemaVersion → 3
├── stats.json                      # MODIFY — add new signal fields per entry (written by pipeline)
├── scripts/
│   ├── refresh.py                  # NO CHANGE — existing GitHub stats refresh
│   └── enrich.py                   # NEW — fetches npm/PyPI/Docker/Smithery signals, computes baseScore, writes stats.json
└── .github/workflows/
    └── refresh.yml                 # NEW — weekly cron: runs refresh.py then enrich.py, commits updated stats.json
```

### mcp-inator changes

```text
mcp-inator/
├── mcp-inator/Models/
│   └── CatalogEntry.swift          # MODIFY — CatalogEntry (add isOfficial, relatedApp, editorialRank; remove isVerified/isFirstParty), CatalogCategory (new enum values + backward-compat decoder), ServerMetrics (add 8 new signal fields), CatalogViewModel (add displayScore, isStale, installCountLabel, starsIsShared)
├── mcp-inator/Services/
│   └── CatalogStore.swift          # MODIFY — add installedApps scan at init, inject into CatalogViewModel, add sortedEntries computed property
├── mcp-inator/UI/
│   └── CatalogView.swift           # MODIFY — CatalogRow signal display row, OfficialBadge rename, browse sort uses sortedEntries with editorial pinned section
└── catalog/
    └── catalog.json                # MODIFY — apply servers.json schema changes to bundled fallback copy
```

---

## Phase 0: Research

*Complete. See [research.md](research.md)*

Key findings:
- Two-repo architecture: pipeline work in `mcp-catalog`, Swift work in `mcp-inator`
- `mcp-catalog/scripts/refresh.py` already handles GitHub stats; add separate `enrich.py` for package registry signals
- `isFirstParty` → `isOfficial` rename (field exists, unused in JSON, active in Swift UI)
- `alternativeTo` reverse-link model already implemented; no changes needed
- `CatalogViewModel` is the right place for `displayScore` computation
- Category raw values must change; backward-compat decoder needed for cached entries
- `githubStarsIsShared` detected automatically by `enrich.py` (multiple entries sharing same repo URL)

---

## Phase 1: Design

*Complete. See [data-model.md](data-model.md)*

---

## Phase 2: Implementation Tasks

Tasks are defined in [tasks.md](tasks.md) (generated by `/speckit-tasks`).

High-level task groups in dependency order:

### Group A — mcp-catalog schema & pipeline (independent of Swift work)

**A1** — Update `servers.json` schema (schemaVersion 3)
- Rename `isFirstParty` → `isOfficial` on all 18 entries, set correct values
- Add `relatedApp` to entries that have a related macOS app (see data-model.md table)
- Add `editorialRank: null` to all entries (except moov-docs: `editorialRank: 1`)
- Update `category` values to new taxonomy slugs
- Remove `isVerified` from all entries
- Add moov-docs entry (see data-model.md for full definition)

**A2** — Write `mcp-catalog/scripts/enrich.py`
- Reads `servers.json` for the entry list and `stats.json` for existing data
- For each entry: fetch npm weekly downloads, PyPI monthly downloads, Docker Hub pulls, Smithery useCount, GitHub commits-by-path (for mono-repos)
- Computes `githubStarsIsShared` (multiple entries sharing same repositoryURL)
- Computes `baseScore` using the log-scale formula
- Writes updated `stats.json`, preserving all existing fields (non-destructive)
- Handles individual API failures gracefully (null field, continue)
- Runnable standalone: `uv run scripts/enrich.py`

**A3** — Add `mcp-catalog/.github/workflows/refresh.yml`
- Weekly cron (Sunday 04:00 UTC)
- Steps: checkout → run `refresh.py` → run `enrich.py` → commit updated `stats.json` if changed
- Uses `GITHUB_TOKEN` (available by default in Actions)

**A4** — Add tests for `enrich.py` scoring formula
- Unit tests in `mcp-catalog/scripts/tests/` covering: score formula correctness, Smithery cap, recency bonus edge cases, mono-repo star-sharing detection

### Group B — mcp-inator Swift model (depends on A1 schema being stable)

**B1** — Update `CatalogEntry` in `CatalogEntry.swift`
- Add `isOfficial: Bool`, `relatedApp: String?`, `editorialRank: Int?`
- Remove `isVerified`, `isFirstParty`
- Custom decoder: `isOfficial = isOfficial ?? isFirstParty ?? false` for backward compat
- Update `CodingKeys` enum

**B2** — Update `CatalogCategory` in `CatalogEntry.swift`
- New enum cases with slug raw values
- Add `label: String` computed property for UI display
- Custom `init(from decoder:)` that accepts both old display-string values and new slug values

**B3** — Update `ServerMetrics` in `CatalogEntry.swift`
- Add 8 new fields: `githubStarsIsShared`, `githubCommits90d`, `npmWeeklyDownloads`, `pypiMonthlyDownloads`, `dockerTotalPulls`, `smitheryUseCount`, `baseScore`, `signalsRefreshedAt`
- All nullable, use `decodeIfPresent` throughout

**B4** — Update `CatalogViewModel` in `CatalogEntry.swift`
- Add `installedApps: Set<String>` parameter to memberwise init
- Add computed properties: `displayScore`, `isStale`, `installCount`, `installCountLabel`, `starsIsShared`, `isOfficial`
- Keep `isTrending` / `trendingScore` on the model (populated by refresh.py, reserved for future use) but stop using them in UI sort/display

**B5** — Update `CatalogStore` in `CatalogStore.swift`
- Add `installedApps: Set<String>` property, populated by `scanInstalledApps()` at init
- Inject `installedApps` into each `CatalogViewModel` during `fetchIfNeeded`
- Add `sortedEntries: [CatalogViewModel]` — editorial pins first, then score-descending, excludes `alternativeTo` entries
- Add `discoverEntries(libraryKeys: Set<String>) -> [CatalogViewModel]` — top-5 scored entries not in user's library and not editorial-pinned; used by Discover section
- Remove `trendingEntries` (replaced by `sortedEntries` + `discoverEntries`)

### Group C — UI updates (depends on B4, B5)

**C1** — Update `CatalogRow` in `CatalogView.swift`
- Replace existing stars + age HStack with signal row: OfficialBadge, installCountLabel, stars with "repo" qualifier, stale warning
- Keep existing layout structure

**C2** — Rename `FirstPartyBadge` → `OfficialBadge` in `CatalogView.swift`
- Same visual; update all call sites
- Wire to `entry.isOfficial` instead of `entry.isFirstParty`

**C3** — Update browse layout in `CatalogView.swift`
- Replace `trendingSection` with two sections when no category filter active:
  - **Editorial section** (entries with non-null `editorialRank`, labeled "Featured")
  - **Discover section** (top-5 high-score entries not in user's library, labeled "Discover", collapses once user has added all 5)
- Replace `entriesByCategory` grouping with flat `sortedEntries` list below the two sections
- When a category filter is active: show only flat filtered list (no Featured/Discover sections)
- Keep category filter chips — they filter `sortedEntries` by category, preserving score order

**C4** — Add search improvements in `CatalogView.swift`
- Search is already functional; update to work correctly against `sortedEntries` (flat list)
- Extend search to match `category.label` in addition to name/description/curatorNote
- Search results are sorted by `displayScore` descending (consistent with browse)
- No other changes to search mechanics needed at this scale

**C5** — Update `RegistryStore.categoryKeywords` map for new category slugs

### Group D — Bundled catalog sync & cleanup (depends on A1, B1-B3)

**D1** — Update `catalog/catalog.json` in `mcp-inator`
- Apply A1 schema changes (same as servers.json): rename isFirstParty → isOfficial, add relatedApp/editorialRank, update categories, remove isVerified
- Add moov-docs entry
- Add stub signal fields to each entry (`null` values; will be populated by pipeline on first run)
- Bump `schemaVersion` to `3`

**D2** — Delete `mcp-inator/scripts/score_probe.py`
- Research artifact, superseded by `mcp-catalog/scripts/enrich.py`
- Manual signal inspection is done via `uv run scripts/enrich.py` in the `mcp-catalog` repo

### Group E — Tests (depends on B1-B5, C1-C4)

**E1** — Unit tests: `CatalogEntry` decoding
- Tests for new fields, backward-compat decoder (old isFirstParty → isOfficial, old category strings)
- Test for null-safe signal field decoding

**E2** — Unit tests: `CatalogViewModel` score computation
- `displayScore` = baseScore when no related app installed
- `displayScore` = baseScore + 3.0 when related app is installed
- `isStale` edge cases (exactly 180 days, 179 days, nil date)
- `installCountLabel` format for npm vs docker values

**E3** — Unit tests: `CatalogStore` sort order and discovery
- Editorial-ranked entries sort before scored entries
- Tied editorial ranks sort by displayScore
- `scanInstalledApps` returns lowercase names without `.app` suffix
- `discoverEntries` excludes entries already in library
- `discoverEntries` excludes editorial-pinned entries
- `discoverEntries` returns at most 5 entries sorted by displayScore

**E4** — Unit tests: `CatalogCategory` backward compat
- Old raw value "Code & Development" decodes to `.developerTools`
- New raw value "developer-tools" decodes to `.developerTools`
