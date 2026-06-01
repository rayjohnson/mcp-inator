# Research: Catalog Signals & Scoring

## Key Discovery: Two-Repo Architecture

The catalog is managed across two separate repos:

| Repo | Role |
|------|------|
| `rayjohnson/mcp-catalog` | Canonical source: `servers.json` (editorial), `stats.json` (metrics), `usage.json`. Has existing `scripts/refresh.py` pipeline. |
| `rayjohnson/mcp-inator` | macOS app. Bundles `catalog/catalog.json` as offline fallback. Fetches live from `mcp-catalog` at runtime. |

**Decision**: Signal pipeline work goes in `mcp-catalog`. Swift model changes go in `mcp-inator`. The `score_probe.py` built during research is a standalone prototype — its logic will be ported into a new `mcp-catalog/scripts/enrich.py`.

---

## Key Discovery: Stats Pipeline Already Exists

`mcp-catalog/scripts/refresh.py` already:
- Reads `servers.json`, fetches GitHub stats per entry
- Writes updated `stats.json` preserving existing fields
- Runs weekly (inferred from docstring)

`stats.json` / `ServerMetrics` already captures: `starCount`, `forkCount`, `lastCommitDate`, `openIssueCount`, `isArchived`, `isTrending`, `trendingScore`.

**Decision**: Add new signal fields (`npmWeeklyDownloads`, `pypiMonthlyDownloads`, `dockerTotalPulls`, `smitheryUseCount`, `baseScore`, `githubStarsIsShared`, `githubCommits90d`) to `stats.json` via a new `scripts/enrich.py` that runs after `refresh.py`. Keeping them separate preserves the existing GitHub refresh logic and makes the signal pipeline independently runnable.

---

## Key Discovery: `isFirstParty` ≈ `isOfficial`

`CatalogEntry` already has `isFirstParty: Bool`. `CatalogView` already renders `FirstPartyBadge()` ("Official" text in blue) when `isFirstParty` is true. However, all 18 current entries have `isFirstParty: false` in `mcp-catalog/servers.json` — the field exists but is unused.

**Decision**: Rename `isFirstParty` → `isOfficial` in both `servers.json` and the Swift model. The Swift decoder falls back to `isFirstParty` during the transition so cached/bundled data doesn't break. `FirstPartyBadge` is renamed `OfficialBadge` but otherwise unchanged.

---

## Key Discovery: `alternativeTo` Already Implemented

`CatalogEntry` has `alternativeTo: String?` (a back-reference from an alternative entry to the canonical entry it replaces). `CatalogStore.alternatives(for:)` and `AlternativesRow` in `CatalogView` are already implemented and working.

**Decision**: Keep the existing `alternativeTo` pattern. The spec's `alternatives` array concept is satisfied by the existing reverse-link model — no structural change needed. We do not add a forward `alternatives` array.

---

## Key Discovery: `CatalogViewModel` is the Right Place for `displayScore`

`CatalogViewModel` already merges `CatalogEntry` + `ServerMetrics` and provides computed properties (`isTrending`, `starCount`, etc.). The installed-app boost computation naturally lives here alongside `baseScore` from `ServerMetrics`.

**Decision**: Add `displayScore: Double` and `isStale: Bool` as computed properties on `CatalogViewModel`. `CatalogStore` adds an `installedApps: Set<String>` property populated at init time, passed into `CatalogViewModel` at construction.

---

## Category Taxonomy Migration

Current Swift enum raw values use display strings ("Code & Development"). New values use slug strings ("developer-tools"). This is a breaking change to `CatalogCategory.rawValue` used as the `category` field in JSON.

**Decision**: Bump `servers.json` `schemaVersion` to `3`. Update all 18 entries in `servers.json`. Update Swift enum raw values. `CatalogCategory.init(from:)` custom decoder handles both old and new values for backward compatibility during the transition window (cached entries).

New taxonomy:
```
developer-tools   (was: Code & Development)
search-web        (was: Web & Browser)
databases         (was: Data & Analytics)
productivity      (was: Productivity, Communication)
ai-memory         (was: AI & LLMs)
infrastructure    (was: Infrastructure)
finance           (new)
```

Note: "Communication" merges into "productivity" since Slack/Gmail are productivity tools.

---

## `githubStarsIsShared` Flag

Stars are shared when multiple catalog entries share the same `repositoryURL`. The `enrich.py` script can detect this automatically: build a map of `repositoryURL → [serverKeys]`; any URL with >1 server key sets `githubStarsIsShared: true` for all of them.

---

## Scoring Formula — Final

Confirmed through probe testing (see `scripts/score_probe.py` output). Works well at discriminating popular vs niche servers with log scale preventing outlier dominance.

```
primaryDist = npmWeeklyDownloads ?? (pypiMonthlyDownloads / 4) ?? 0
baseScore =
    log10(primaryDist + 1)                         × 3.0
  + log10(dockerTotalPulls + 1)                    × 1.0
  + log10(min(smitheryUseCount, 100_000) + 1)      × 1.5
  + 5.0  if isOfficial
  + recencyBonus (+2 if lastCommitDate < 90d, 0 if < 1yr, −2 otherwise)
```

Smithery cap at 100,000 guards against the confirmed Math-MCP anomaly (1.6M useCount, clearly gamed/infrastructure).

---

## GitHub Actions CI for `mcp-catalog`

`mcp-inator` already has a CI workflow. `mcp-catalog` will need a new `refresh.yml` workflow (if one doesn't exist) or an extension to run `enrich.py` after `refresh.py`. The workflow commits updated `stats.json` back to `main`. Requires `GITHUB_TOKEN` (available by default in Actions), npm API (no auth needed), pypistats (no auth), Docker Hub (no auth), Smithery (no auth).
