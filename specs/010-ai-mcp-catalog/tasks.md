---
description: "Task list for AI-Curated MCP Server Catalog"
---

# Tasks: AI-Curated MCP Server Catalog

**Input**: Design documents from `/specs/010-ai-mcp-catalog/`

**Prerequisites**: plan.md, spec.md, data-model.md, research.md, contracts/

**Organization**: Tasks grouped by user story. Two repos involved:
- `mcp-catalog/` = new `rayjohnson/mcp-catalog` public GitHub repo
- `mcp-inator/` = existing `rayjohnson/mcp-inator` app repo (this branch)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: Which user story (US1–US5) from spec.md

---

## Phase 1: Setup (Shared Catalog Repo Infrastructure)

**Purpose**: Create the `rayjohnson/mcp-catalog` repo structure and initial JSON files. All subsequent pipeline and app work depends on these files existing with correct schemas.

- [ ] T001 Create mcp-catalog repo directory layout and root README.md with curator workflow, label guide, and weekly job overview
- [ ] T002 [P] Create mcp-catalog/servers.json initial file (schemaVersion 2, one complete sample entry with all fields per contracts/servers-json.md)
- [ ] T003 [P] Create mcp-catalog/stats.json initial file (schemaVersion 2, empty servers object per contracts/stats-json.md — includes GitHub stats, sentiment, and usage count sections)
- [ ] T004 [P] Create mcp-catalog/usage.json initial file (internal Worker accumulator, schemaVersion 1, empty usage object per contracts/usage-json.md — NOT fetched by app)
- [ ] T005 [P] Create mcp-catalog/.github/ISSUE_TEMPLATE/config.yml to disable blank issues and direct users to the submission template
- [ ] T005b [P] Create mcp-catalog/config.json: pipeline config file with initial subreddit list (r/ClaudeAI, r/ClaudeCode, r/MCPservers) and lastSubredditReviewDate field; read by sentiment.py each run; updated by AI on monthly cadence

---

## Phase 2: Foundational (Blocking — App-Side Data Model)

**Purpose**: Swift model and bundled catalog update that ALL app-side user stories depend on. Must be complete before any UI work begins.

**⚠️ CRITICAL**: US1, US5 app tasks cannot start until T006–T009 are complete.

- [ ] T006 Create mcp-inator/Models/CatalogEntry.swift with Codable structs: CatalogEntry (all fields per contracts/servers-json.md including curatorNote, isFirstParty, alternativeTo, requiredArgs), EnvVarDefinition, RequiredArgDefinition, ServerMetrics (all fields per contracts/stats-json.md — GitHub stats + sentiment + usage counts) — all optional fields use decodeIfPresent
- [ ] T007 Add CatalogViewModel struct to mcp-inator/Models/CatalogEntry.swift: joins CatalogEntry + ServerMetrics? into single display model; all ServerMetrics fields are optional and degrade to nil gracefully
- [ ] T008 Update mcp-inator/Resources/catalog.json to schemaVersion 2: add curatorNote, isFirstParty (false), alternativeTo (null), requiredArgs ([]) to all 18 existing entries with realistic placeholder curator notes
- [ ] T009 Update project.yml to include new Swift source files, then run `xcodegen generate` to register them in mcp-inator.xcodeproj/project.pbxproj
- [ ] T009b Add `isPrivate` attribute (Bool, default false) to the MCPServerConfig Core Data entity in mcp-inator/Models/mcp_inator.xcdatamodeld; create a lightweight migration; update MCPServerConfig to expose the property; update ConfigStore to persist the flag

**Checkpoint**: Build must succeed (`xcodebuild ... build`) before proceeding to US1 tasks.

---

## Phase 3: User Story 1 — Rich Catalog Display (Priority: P1) 🎯 MVP

**Goal**: App fetches from `rayjohnson/mcp-catalog` and renders enriched entries with curator notes, first-party badges, star counts, env var documentation, and trending signals.

**Independent Test**: Populate `mcp-catalog/servers.json` with 10 hand-crafted entries. Launch the app, open Catalog tab, verify: curator note shown, first-party badge visible on eligible entries, env vars listed with descriptions, documentation link works, trending badge appears for score ≥ 70.

- [ ] T010 [P] [US1] Create mcp-inator/Services/CatalogClient.swift: fetch servers.json and stats.json in parallel using `async let`; on any network failure fall back to bundled mcp-inator/Resources/catalog.json; cache result to App Support/mcp-inator/catalog-cache.json on success
- [ ] T011 [P] [US1] Create mcp-inator/Services/CatalogStore.swift: @MainActor ObservableObject; holds [CatalogViewModel]; exposes trendingEntries (where ServerMetrics.isTrending == true) and entriesByCategory; fetches once per session; loads from cache on init
- [ ] T012 [US1] Wire CatalogClient and CatalogStore into mcp-inator/App/mcp_inatorApp.swift: instantiate CatalogStore as @StateObject, inject into environment
- [ ] T013 [US1] Update mcp-inator/UI/CatalogView.swift to use CatalogStore: (1) add Trending section at top for entries where isTrending == true (ordered by trendingScore descending); (2) show first-party badge, star count, last-commit recency chip, one-line curator note preview on entry rows; (3) implement same-service grouping using `alternativeTo` — recommended pick shown at full size, alternatives collapsed behind a "N alternatives" disclosure control that expands inline
- [ ] T014 [US1] Create mcp-inator/UI/CatalogEntryDetailView.swift: full detail sheet with curator note, all env vars (name + description + required/sensitive badges), usage count ("used by N mcp-inator users"), documentation link, recommended-vs-alternative indicator (alternativeTo), GitHub stats
- [ ] T015 [P] [US1] Create mcp-inatorTests/Unit/CatalogEntryTests.swift: decoder tests against fixture JSON files covering schemaVersion 2 with all new fields, missing optional fields (degrades gracefully), alternativeTo self-reference
- [ ] T016 [US1] Verify offline fallback in CatalogClient: write a test or manually confirm that when all fetches fail the app shows bundled catalog.json entries without any error UI

**Checkpoint**: US1 fully functional — user can browse, read curator notes, see env var requirements, and add a server without visiting external docs.

---

## Phase 4: User Story 2 — Community Submission Pipeline (Priority: P1)

**Goal**: A GitHub Issue with a repo URL triggers AI enrichment and produces a draft PR within 10 minutes.

**Independent Test**: Open a real GitHub Issue in `mcp-catalog` with the submission template and a valid MCP server URL. Verify a draft PR appears within 10 minutes with all required fields populated from the repo's README.

- [ ] T017 [US2] Create mcp-catalog/.github/ISSUE_TEMPLATE/submit-server.yml: structured form with required `server_identifier` field (any of: repo URL, npm package name, PyPI/uvx package name, Docker image — examples shown in field description), optional `why_i_like_it` textarea, instructions about expected pipeline behavior
- [ ] T018 [US2] Create mcp-catalog/.github/workflows/enrich-submission.yml: trigger on `issues: types: [labeled]` where label is `submission`; job runs `pip install anthropic requests PyGithub` then `scripts/enrich.py`; uses `peter-evans/create-pull-request@v8` to open draft PR; `timeout-minutes: 15`; injects `ANTHROPIC_API_KEY` and `GITHUB_TOKEN` from secrets
- [ ] T019 [US2] Create mcp-catalog/scripts/enrich.py: (1) extract server_identifier from issue body; (2) detect identifier type (repo URL, npm package, PyPI/uvx package, Docker image) and resolve accordingly — repo URL: fetch README from that host; npm: fetch registry.npmjs.org metadata + README; PyPI/uvx: fetch pypi.org metadata + linked docs; Docker: fetch Docker Hub description; (3) if identifier cannot be resolved from any source, comment on issue explaining what was tried and exit without PR; (4) call Claude API with all fetched content to produce a complete CatalogEntry JSON, flagging fields that could not be inferred; (5) check for duplicate (matching repositoryURL or package identifier already in servers.json) — if duplicate, comment on issue and exit without PR; (6) if service already cataloged under different identifier, include comparison comment on PR; (7) write enriched entry to temp file for peter-evans action to stage
- [ ] T020 [US2] Add "submission" label to mcp-catalog repo (document manual step); add test cases to mcp-catalog/scripts/tests/test_enrich.py covering: valid GitHub URL, valid npm package name, valid uvx package name, duplicate submission, unresolvable identifier (should comment + close)

**Checkpoint**: US2 independently testable — open a real issue, pipeline fires, PR appears.

---

## Phase 5: User Story 3 — Weekly Freshness (Priority: P2)

**Goal**: Stats stay current; archived repos and env-var drift are flagged automatically.

**Independent Test**: Manually dispatch `weekly-refresh.yml`. Verify `stats.json` is updated in the catalog repo commit history with current star counts. Alter a test entry to have wrong env vars; verify a drift PR is opened.

- [ ] T021 [US3] Create mcp-catalog/.github/workflows/weekly-refresh.yml: cron `0 2 * * 1` (Monday 2am UTC); runs `scripts/refresh.py`; commits stats.json update directly (no PR needed for stats); opens individual PRs for entries with significant drift (archived, env-var changes); injects `GITHUB_TOKEN` and `ANTHROPIC_API_KEY`
- [ ] T022 [US3] Create mcp-catalog/scripts/refresh.py: (1) read servers.json; (2) for each entry, call GitHub REST API for starCount, forkCount, lastCommitDate, openIssueCount, isArchived; (3) read usage.json and fold userCount/enabledCount/weeklyActiveCount into per-entry metrics; (4) write complete stats.json (preserving any existing sentiment fields); (5) for archived repos open a PR flagging the entry for removal; (6) diff current README env vars against catalog envVars using Claude; open drift PR if mismatch found

**Checkpoint**: US3 independently testable via manual workflow dispatch.

---

## Phase 6: User Story 5 — Anonymous Usage Sharing (Priority: P2)

**Goal**: Opt-in telemetry flow → per-server "used by N users" counts in catalog.

**Independent Test**: Enable sharing in debug settings. Open SharingReviewView, verify sanitized payload matches telemetry-payload contract (no values, paths replaced with `[path]`). Submit. Verify usage.json (internal Worker file) reflects incremented count. After next weekly refresh cycle, verify counts appear in stats.json.

- [ ] T023 [US5] Create mcp-catalog/cloudflare-worker/index.js: handle `POST /report`; validate schemaVersion; for each server entry increment usage.json via GitHub Contents API (GET for SHA → PUT updated content); flag isKnownCatalogEntry:false entries in candidate-submissions.json; discard sessionToken; never log client IP; return `{"status":"ok","accepted":N}`
- [ ] T024 [US5] Add Cloudflare Worker deployment documentation to mcp-catalog/cloudflare-worker/README.md: wrangler setup, required secrets (fine-grained PAT scoped to `rayjohnson/mcp-catalog` Contents read+write), deploy command
- [ ] T025 [US5] Create mcp-inator/Services/UsageSharingService.swift: build SanitizedServerEntry from MCPServerConfig per Decision 6 rules (command allowlist, path redaction, env-var key-only); construct UsageReport payload; POST to Cloudflare Worker URL; retry up to 3× with exponential backoff; queue locally in UserDefaults on failure; retry on next launch; drop after 3 failed attempts silently
- [ ] T026 [P] [US5] Create mcp-inator/UI/SharingConsentView.swift: non-intrusive prompt shown when firstLaunchDate > 7 days ago AND ≥1 enabled server; two actions: "Review what I'd share" (leads to SharingReviewView) and "Not now" (defers, never auto-submits)
- [ ] T027 [P] [US5] Create mcp-inator/UI/SharingReviewView.swift: show each opted-in server's sanitized fields (serverKey, command, sanitizedArgs, envVarKeys); per-server toggle to exclude; "Submit" button calls UsageSharingService; "Cancel" exits without submitting
- [ ] T028 [US5] Add sharing preference keys to UserDefaults and update mcp-inator/UI/SettingsView.swift: "Contributing Usage Data" section with current opt-in status, "Withdraw participation" button (prevents future submissions), link to privacy explanation
- [ ] T029 [US5] Wire sharing eligibility check into mcp-inator/App/mcp_inatorApp.swift: on app foreground, evaluate eligibility (days since first launch, enabled server count, not already shown this session); present SharingConsentView as sheet when eligible
- [ ] T029b [P] [US5] Add "Private server" toggle (isPrivate) to the server edit view (mcp-inator/UI/ServerEditView.swift or equivalent): Boolean toggle with label "Keep private — exclude from usage sharing and catalog statistics"; wired to MCPServerConfig.isPrivate via ConfigStore; UsageSharingService must filter out isPrivate servers before constructing the payload

**Checkpoint**: US5 independently testable — full flow from consent prompt → review → submit → usage.json updated.

---

## Phase 7: User Story 4 — Reddit Sentiment Signals (Priority: P3)

**Goal**: Weekly Reddit mention analysis produces one-line sentiment summaries and trending scores folded into stats.json, displayed in the app.

**Independent Test**: Manually dispatch `weekly-sentiment.yml`. Verify `stats.json` is updated with non-empty sentimentSummary and trendingScore fields for servers with known Reddit discussion. Verify app shows them in Trending section.

- [ ] T030 [US4] Create mcp-catalog/.github/workflows/weekly-sentiment.yml: cron `0 4 * * 1` (Monday 4am UTC, after refresh); runs `scripts/sentiment.py`; commits updated stats.json (sentiment fields only); injects only `ANTHROPIC_API_KEY` from secrets (no Reddit credentials needed — uses public JSON API); if Reddit returns errors, exits 0 without touching stats.json
- [ ] T031 [US4] Create mcp-catalog/scripts/sentiment.py: (1) read active subreddit list from config.json; (2) for each catalog entry, search active subreddits using Reddit's public JSON API (no auth required): `GET https://www.reddit.com/r/{sub}/search.json?q={name}&sort=new&limit=100&t=month` with `User-Agent: mcp-catalog-bot/1.0` header; (3) collect post titles, scores, comment counts from last 30 days; (4) for servers with ≥1 mention: call Claude to produce sentimentSummary + trendingScore (0–100); (5) compute isTrending flag based on score distribution (e.g. servers in top quartile of scored entries that week); (6) read existing stats.json and patch sentiment fields (isTrending, trendingScore, sentimentSummary, mentionCount, periodDays, sentimentComputedAt) for each server; servers with 0 mentions have all sentiment fields removed and isTrending set to false; write updated stats.json; (7) if lastSubredditReviewDate in config.json is >30 days ago, ask Claude to evaluate current subreddit list and discover emerging MCP communities — update config.json subreddit list and lastSubredditReviewDate if changes recommended; sleep 2s between subreddit requests to stay within rate limits
- [ ] T032 [US4] Update mcp-inator/UI/CatalogEntryDetailView.swift to display sentimentSummary when present on the ServerMetrics model; confirm CatalogView.swift Trending section already works from T013 (trendingScore threshold already wired via CatalogStore)

**Checkpoint**: US4 independently testable — manual dispatch of sentiment workflow, app shows updated trending data.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Pre-merge housekeeping, settings polish, and release prep.

- [ ] T033 Update mcp-inator/UI/SettingsView.swift sharing section: ensure "Withdraw participation" correctly clears opt-in state and displays confirmation; verify withdrawn state persists across app restarts
- [ ] T034 [P] Run `make test` in mcp-inator repo and fix any regressions introduced by new Swift files; confirm all existing tests still pass
- [ ] T035 [P] Add mcp-catalog/scripts/tests/test_refresh.py with basic assertions for stats.json output shape and drift detection logic
- [ ] T036 Bump VERSION and update RELEASE_NOTES.md in mcp-inator repo before PR merge

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately in mcp-catalog repo
- **Foundational (Phase 2)**: No dependencies on Phase 1 — can start immediately in mcp-inator repo
- **US1 (Phase 3)**: Depends on Foundational (T006–T009 complete)
- **US2 (Phase 4)**: Depends on Phase 1 (mcp-catalog JSON files exist); independent of US1
- **US3 (Phase 5)**: Depends on Phase 1 (mcp-catalog JSON files) and US2 (servers.json has entries); independent of US1
- **US5 (Phase 6)**: Depends on Foundational (T006–T009) and Phase 1 (usage.json accumulator exists); can parallel with US1 after Foundational
- **US4 (Phase 7)**: Depends on Phase 1 (stats.json exists) and US3 (refresh runs first weekly, establishing the file structure sentiment.py patches); independent of US1/US5
- **Polish (Phase 8)**: Depends on all desired stories complete

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational — no dependency on mcp-catalog pipeline
- **US2 (P1)**: Can start after Phase 1 (Setup) — entirely in mcp-catalog repo, no app dependency
- **US3 (P2)**: Can start after Phase 1 and US2 merges at least one entry
- **US5 (P2)**: Can start after Foundational — app-side only until Worker deployment
- **US4 (P3)**: Can start after Phase 1 — entirely in mcp-catalog repo

### Within Each User Story

- Models before services; services before UI
- CatalogClient (T010) and CatalogStore (T011) can be developed in parallel
- SharingConsentView (T026) and SharingReviewView (T027) can be developed in parallel
- mcp-catalog Python scripts (enrich.py, refresh.py, sentiment.py) are independent of each other

### Parallel Opportunities

```bash
# Phase 1 — all setup tasks in parallel:
T002 Create servers.json
T003 Create stats.json (expanded schema)
T004 Create usage.json (internal accumulator)
T005 Create .github/ISSUE_TEMPLATE/config.yml

# Phase 2 + Phase 1 simultaneously (different repos):
T006–T009 (mcp-inator model work) || T001–T005 (mcp-catalog repo setup)

# Phase 3 US1 — client and store in parallel:
T010 CatalogClient.swift
T011 CatalogStore.swift
T015 CatalogEntryTests.swift

# Phase 6 US5 — consent and review views in parallel:
T026 SharingConsentView.swift
T027 SharingReviewView.swift
```

---

## Implementation Strategy

### MVP: User Story 1 Only

1. Complete Phase 1 (Setup) — populate mcp-catalog with hand-crafted entries
2. Complete Phase 2 (Foundational) — Swift model and bundled catalog update
3. Complete Phase 3 (US1) — rich catalog display in app
4. **STOP and VALIDATE**: Open catalog tab, verify all new fields render
5. This delivers SC-001 (user can find and add a server in under 2 minutes)

### Incremental Delivery

1. Foundation + US1 → Rich catalog display (MVP — ship this first)
2. Add US2 → Community submission pipeline (first AI-enriched entries)
3. Add US3 + US5 → Freshness + usage telemetry (living catalog)
4. Add US4 → Trending signals (polish)
5. Each story adds value independently

### Parallel Team Strategy

Two independent workstreams after Phase 1:
- **App track**: Foundational → US1 → US5
- **Pipeline track**: US2 → US3 → US4 (all in mcp-catalog repo)

---

## Notes

- `[P]` = different files, no blocking dependencies between them
- mcp-catalog tasks run in a separate repo from mcp-inator tasks — no project.yml/xcodegen needed for pipeline work
- `touch` edited Swift files before `xcodebuild` to force recompilation
- Run `xcodegen generate` after any new Swift files are added to project.yml
- Run `make test` before each PR merge
- Bump VERSION + update RELEASE_NOTES.md before every merge (required by project standards)
- PRs from `peter-evans/create-pull-request@v8` using `GITHUB_TOKEN` do NOT trigger `pull_request` CI — this is expected (documented in research.md Decision 1)
- Cloudflare Worker PAT must be a fine-grained token scoped only to `rayjohnson/mcp-catalog` Contents read+write — never embed in app binary
