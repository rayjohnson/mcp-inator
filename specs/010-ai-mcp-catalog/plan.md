# Implementation Plan: AI-Curated MCP Server Catalog

**Branch**: `010-ai-mcp-catalog` | **Date**: 2026-05-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/010-ai-mcp-catalog/spec.md`

---

## Summary

Build a curated, AI-enriched MCP server catalog backed by a separate public GitHub repository (`rayjohnson/mcp-catalog`). Community members submit servers via GitHub Issues; a GitHub Actions pipeline calls Claude to auto-populate catalog entries and open draft PRs for curator review. Weekly jobs keep stats fresh and compute Reddit sentiment scores. mcp-inator fetches three raw JSON files (servers.json, stats.json, trending.json) at launch and renders richer catalog entries with curator notes, first-party badges, env var documentation, and trending signals. An opt-in usage telemetry flow routes anonymous payloads through a Cloudflare Worker to produce per-server usage counts.

---

## Technical Context

**Language/Version**: Swift 5.9 (macOS app), Python 3.11 (GitHub Actions pipeline scripts), JavaScript ES2022 (Cloudflare Worker)

**Primary Dependencies**:
- App: SwiftUI, URLSession (already in project), Foundation JSON decoder
- Pipeline: `anthropic` Python SDK (pip), `requests` (pip), `PyGithub` (pip)
- Worker: Cloudflare Workers runtime, GitHub Contents REST API (v3)

**Storage**:
- Catalog data: Two JSON files in `rayjohnson/mcp-catalog` GitHub repo (free CDN via raw.githubusercontent.com): `servers.json` (curated entries) and `stats.json` (all computed metrics)
- App cache: `App Support/mcp-inator/catalog-cache.json` (session cache, existing pattern)
- Worker accumulator: `usage.json` in catalog repo (written by Cloudflare Worker in real-time; read by weekly refresh job; never fetched by app)

**Testing**:
- App: XCTest (existing), fixture JSON files for catalog decoder tests
- Pipeline: pytest for Python enrichment logic; GitHub Actions manual workflow dispatch for integration tests
- Worker: Cloudflare Workers local dev (`wrangler dev`) for unit testing

**Target Platform**: macOS 13+ (app), GitHub Actions ubuntu-latest runners (pipeline), Cloudflare Workers free tier (telemetry)

**Performance Goals**:
- App catalog load < 2 seconds (three parallel fetches on fast connection)
- AI pipeline PR generation < 10 minutes from issue creation
- Worker response < 500ms p95

**Constraints**:
- Zero infrastructure hosting cost
- AI API cost < $5/month at steady state (~200 catalog entries, weekly refresh, ~20 submissions/week)
- No automated PR merges — all entries require human curator review
- App binary must NOT contain any writable GitHub token

**Scale/Scope**: ~200 catalog entries at steady state; app catalog tab replaces/supplements current `registry.modelcontextprotocol.io` integration

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Native macOS Experience | ✅ PASS | All new UI uses SwiftUI. Catalog tab follows HIG. No web views. |
| II. Single Source of Truth | ✅ PASS | Catalog is read-only reference data. User library (ConfigStore) remains authoritative. |
| III. Non-Destructive Configuration | ✅ PASS | Browsing or refreshing catalog never touches user's config store. Adding from catalog is additive. |
| IV. Config Portability | ✅ PASS | No change to how configs apply across agents. CatalogEntry → MCPServerConfig conversion is additive. |
| V. Simplicity & Discoverability | ✅ PASS | Richer catalog with env var docs and curator notes reduces setup friction — directly serves this principle. |

**Post-design re-check**: All gates continue to pass. The Cloudflare Worker is external infrastructure but is zero-maintenance free tier, doesn't affect the app's native feel, and its token never appears in the binary.

---

## Project Structure

### Documentation (this feature)

```text
specs/010-ai-mcp-catalog/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── spec.md              # Feature specification
├── checklists/
│   └── requirements.md
├── contracts/
│   ├── servers-json.md       # servers.json schema
│   ├── stats-json.md         # stats.json schema
│   ├── trending-json.md      # trending.json schema
│   ├── usage-json.md         # usage.json schema
│   └── telemetry-payload.md  # POST payload to Cloudflare Worker
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code

This feature spans two repositories:

#### rayjohnson/mcp-catalog (new public repo)

```text
mcp-catalog/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── submit-server.yml          # Structured issue form: GitHub URL + freetext
│   └── workflows/
│       ├── enrich-submission.yml      # Triggered by issue label; calls enrich.py; opens draft PR
│       ├── weekly-refresh.yml         # Cron: updates stats.json (GitHub stats + usage fold-in); opens drift PRs
│       └── weekly-sentiment.yml       # Cron: searches Reddit; patches sentiment fields in stats.json
├── scripts/
│   ├── enrich.py                      # AI enrichment: reads repo → populates catalog entry
│   ├── refresh.py                     # Stats refresh: GitHub API → stats.json; folds usage.json counts in
│   └── sentiment.py                   # Reddit search → Claude → patches stats.json sentiment fields
├── cloudflare-worker/
│   └── index.js                       # Telemetry Worker: receives reports, accumulates usage.json (internal)
├── servers.json                       # Curated catalog entries (hand-reviewed) — APP-FACING
├── stats.json                         # All computed metrics: GitHub stats + sentiment + usage — APP-FACING
├── usage.json                         # Internal Worker accumulator (NOT fetched by app)
└── config.json                        # Pipeline config: active subreddit list (AI-managed, NOT fetched by app)
```

#### rayjohnson/mcp-inator (existing repo, this branch)

```text
mcp-inator/
├── Models/
│   └── CatalogEntry.swift             # New: extended catalog model + RegistryEntry bridge
├── Services/
│   ├── CatalogClient.swift            # New: fetches servers/stats/trending/usage in parallel
│   └── CatalogStore.swift             # New: in-memory merged view; replaces RegistryStore for catalog tab
└── UI/
    ├── CatalogView.swift              # Updated: render new fields (curatorNote, firstParty, stars, etc.)
    ├── CatalogEntryDetailView.swift   # New or updated: full detail with env vars, curator note, usage
    ├── SharingReviewView.swift        # New: shows sanitized payload, per-server toggles
    └── SharingConsentView.swift       # New: initial opt-in prompt
mcp-inatorTests/
└── Unit/
    ├── CatalogEntryTests.swift        # Decoder tests with fixture JSON
    └── CatalogClientTests.swift       # Mock URL session tests
mcp-inator/Resources/
└── catalog.json                       # Updated bundled fallback with new fields
```

**Structure Decision**: Two-repo architecture (Decision 5 in research.md). The catalog repo is independently forkable by other tools; its git history isn't polluted by app code changes. The mcp-inator changes are confined to the existing project structure, extending rather than replacing `RegistryEntry`.

---

## Implementation Phases

### US1: Rich Catalog Display (P1)

**Goal**: App fetches from mcp-catalog repo and renders enriched entries.

**Approach**:
1. Create `CatalogEntry.swift` — new Codable model with all fields from contracts/servers-json.md. Include a `init(catalogEntry:)` on `MCPServerConfig` for adding to library.
2. Create `CatalogClient.swift` — fetches three URLs in parallel (`async let`). Falls back to bundled `catalog.json` on any network failure. Caches result to `App Support/mcp-inator/catalog-cache.json`.
3. Update `CatalogView` to show: first-party badge, star count, last-commit recency, trending badge (score ≥ 70), curator note, full env var list with descriptions.
4. Update bundled `catalog.json` to schemaVersion 2 with new fields.

**Independent test**: Manually populate `servers.json` with 10 entries in the catalog repo and verify the app renders all new fields before building any pipeline.

---

### US2: Community Submission Pipeline (P1)

**Goal**: GitHub Issue → AI enrichment → draft PR, within 10 minutes.

**Approach**:
1. Create `submit-server.yml` issue template in mcp-catalog repo.
2. Create `enrich-submission.yml` Action: triggers on `issues: labeled` with label `submission`; runs `enrich.py`; uses `peter-evans/create-pull-request@v8` to open draft PR.
3. Write `enrich.py`: extracts GitHub URL from issue body; fetches README + package files via GitHub API; calls Claude API with structured prompt; outputs a complete `servers.json` entry; handles duplicate detection (same `repositoryURL` already in file → comment + close, no PR).
4. Test: open a real issue with a known MCP server URL; verify PR appears with populated fields.

**Key constraint**: `ANTHROPIC_API_KEY` is a GitHub Actions secret. `timeout-minutes: 15` on the job. PRs created with `GITHUB_TOKEN` don't trigger `pull_request` workflows — this is fine.

---

### US3: Weekly Freshness (P2)

**Goal**: Stats stay current; drifted/archived entries get flagged.

**Approach**:
1. Create `weekly-refresh.yml` Action: cron `0 2 * * 1` (Monday 2am UTC); runs `refresh.py`.
2. Write `refresh.py`: reads `servers.json`; for each `repositoryURL`, calls GitHub REST API for stats; writes `stats.json`; for archived repos or significant env-var drift → opens a PR flagging the entry.
3. Test: manually dispatch the workflow; verify `stats.json` is updated in the catalog repo commit history.

---

### US4: Reddit Sentiment (P3)

**Goal**: Weekly sentiment scores and one-line summaries in trending.json.

**Approach**:
1. Create `weekly-sentiment.yml` Action: cron `0 4 * * 1` (Monday 4am UTC, after refresh); runs `sentiment.py`.
2. Write `sentiment.py`: for each catalog entry, searches Reddit via OAuth (client-credentials flow); passes recent posts to Claude; Claude produces `sentimentSummary` + `trendingScore`; writes `trending.json`. Skips servers with 0 recent mentions (entry omitted).
3. Store `REDDIT_CLIENT_ID` and `REDDIT_CLIENT_SECRET` as GitHub Actions secrets.
4. Test: run workflow manually against 5 entries with known Reddit discussion.

---

### US5: Anonymous Usage Sharing (P2)

**Goal**: Opt-in usage telemetry → "used by N users" counts in catalog.

**Approach**:
1. Create `SharingConsentView.swift`: shown after 7+ days of use with ≥1 enabled server. Non-intrusive. Leads to review screen.
2. Create `SharingReviewView.swift`: shows sanitized payload per the telemetry-payload contract. Per-server toggle to exclude. "Submit" sends POST to Cloudflare Worker.
3. Add sharing opt-in/out to Settings. Store preference in UserDefaults.
4. Create Cloudflare Worker (`cloudflare-worker/index.js`): receives POST; updates `usage.json` via GitHub Contents API (GET for SHA → PUT); discards session token; stores fine-grained PAT as encrypted Worker secret.
5. Test: enable sharing in debug build; verify review screen shows sanitized payload (no values, no paths); submit; verify `usage.json` updated in catalog repo.

---

## Complexity Tracking

No constitution violations. The Cloudflare Worker is the only infrastructure addition and runs on free tier with no maintenance burden.
