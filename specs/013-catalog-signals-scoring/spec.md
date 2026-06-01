# Feature Specification: Catalog Signals & Scoring

**Feature Branch**: `013-catalog-signals-scoring`

**Created**: 2026-06-01

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Browse catalog with confidence signals (Priority: P1)

A user opens the mcp-inator catalog to find an MCP server. Instead of an undifferentiated flat list, entries show inline trust and popularity signals: whether the server is from the official upstream project, how many people install it weekly, and a warning if it hasn't been updated in months. The default sort order puts the most useful, trusted servers first without requiring the user to know what to look for.

**Why this priority**: Core value proposition of the feature. Delivers immediately on "opinionated catalog" without requiring any of the pipeline or personalization work.

**Independent Test**: Can be tested by loading a catalog.json that already has signal fields populated (can be hand-crafted for the test) and verifying the list renders correctly with badges, counts, and sort order.

**Acceptance Scenarios**:

1. **Given** the catalog is open, **When** a user scrolls the list, **Then** each entry shows an "Official" badge if `isOfficial` is true, a formatted install count if signal data is present, and GitHub stars with a "(repo)" qualifier if `githubStarsIsShared` is true.
2. **Given** a server whose `lastCommitDate` is more than 6 months ago, **When** it appears in the list, **Then** it shows a subtle amber stale-activity indicator.
3. **Given** the catalog has loaded, **When** no explicit sort is selected, **Then** entries are ordered by `displayScore` descending, with any `editorialRank`-pinned entries appearing first as a separate pinned section.
4. **Given** a server with no signal data (all signal fields null), **When** it appears in the list, **Then** signal slots are simply empty — no error state, no placeholder text.

---

### User Story 2 — Personalized relevance for installed apps (Priority: P2)

A user who has Notion installed on their Mac opens the catalog. The Notion MCP server is boosted in sort order — not to a pinned position, but meaningfully higher than its raw signal score would place it — because mcp-inator detected that Notion is installed and inferred the user is likely to want it.

**Why this priority**: High user value with low implementation cost. Makes the catalog feel smart without requiring any user configuration.

**Independent Test**: Can be tested by mocking the installed-app list to include "Notion" and verifying the Notion entry's `displayScore` is 3.0 higher than its `baseScore`, and that its sort position reflects this.

**Acceptance Scenarios**:

1. **Given** Notion.app is present in `/Applications` or `~/Applications`, **When** the catalog loads, **Then** the Notion entry's `displayScore` equals its `baseScore` plus the installed-app boost (3.0).
2. **Given** Linear.app is not installed, **When** the catalog loads, **Then** the Linear entry's `displayScore` equals its `baseScore` with no boost applied.
3. **Given** an entry has no `relatedApp` field, **When** the app scan runs, **Then** no boost is applied and no error occurs.
4. **Given** the user installs a new app after mcp-inator launched, **When** they relaunch mcp-inator, **Then** the installed-app scan re-runs and the boost is applied on the next catalog load.

---

### User Story 3 — Signal data stays fresh via automated pipeline (Priority: P3)

The catalog's signal data (download counts, Smithery use counts, GitHub activity) is refreshed weekly by an automated CI job. The app bundles the latest enriched `catalog.json` at build time, so users always get reasonably current signal data without any runtime API calls from the app.

**Why this priority**: Makes the signals trustworthy over time. Without it, signal data goes stale and loses credibility. Lower than P1/P2 because the initial catalog.json can be hand-populated to unblock UI work.

**Independent Test**: Can be tested by running the pipeline script manually, verifying it updates only signal fields in catalog.json without touching editorial fields, and confirming the output passes JSON schema validation.

**Acceptance Scenarios**:

1. **Given** the pipeline runs, **When** it completes, **Then** every entry in catalog.json has its `signals.*` fields and `baseScore` updated and `signals.refreshedAt` set to the current timestamp.
2. **Given** an entry has `editorialRank`, `isOfficial`, or `relatedApp` set by a human, **When** the pipeline runs, **Then** those fields are unchanged in the output.
3. **Given** an API is unavailable during a pipeline run (e.g., Smithery times out), **When** the pipeline completes, **Then** the affected signal field is set to null rather than failing the whole run, and existing values for other signals are still updated.
4. **Given** a new entry is added to catalog.json with no signal fields, **When** the pipeline runs, **Then** signals are fetched and populated for the new entry.

---

### Edge Cases

- What happens when all signal fields are null (new entry, APIs all unavailable)? Entry renders without signal UI; sort places it below scored entries.
- What happens when `smitheryUseCount` is anomalously high (e.g., 1.6M due to infrastructure abuse)? The scoring formula caps Smithery contribution at 100k before applying log scale, limiting damage to the sort order.
- What happens when `githubStarsIsShared` is true and stars are, say, 87k? The UI displays "87k⭐ repo" with the "repo" qualifier to signal that this count reflects the whole mono-repo, not this server alone.
- What happens when two entries have the same `editorialRank`? They are sorted by `displayScore` within that rank tier.
- What happens when `/Applications` scan fails due to permissions? Scan fails silently; no boosts applied; no error surfaced to user.

## Requirements *(mandatory)*

### Functional Requirements

**Schema (catalog.json)**

- **FR-001**: The catalog schema MUST be bumped to version 3 with the addition of new editorial and signal fields. (Note: the catalog is stored across two files in `mcp-catalog` — `servers.json` for editorial fields and `stats.json` for signals; both are updated as part of this schema version bump.)
- **FR-002**: Each entry MUST support the following new editorial fields (human-owned, never overwritten by the pipeline): `isOfficial` (bool), `relatedApp` (string | null — the macOS app name as it appears in Finder, e.g. "Notion"; see data-model.md for the initial value table), `editorialRank` (int | null). Note: alternatives relationships are satisfied by the existing `alternativeTo` reverse-link field already present in the schema; no forward `alternatives` array is required.
- **FR-003**: The `isVerified` field MUST be removed from the schema and all existing entries.
- **FR-004**: The `category` field values MUST be updated to the new taxonomy: `developer-tools`, `search-web`, `databases`, `productivity`, `ai-memory`, `infrastructure`, `finance`.
- **FR-005**: The server metrics record MUST be extended with new signal fields stored flat (not nested): `npmWeeklyDownloads`, `pypiMonthlyDownloads`, `dockerTotalPulls`, `smitheryUseCount`, `githubStarsIsShared` (bool), `githubCommits90d`, `signalsRefreshedAt`. All numeric fields are nullable. These join the existing `starCount` and `lastCommitDate` fields already present in the metrics record; `starCount` serves as the GitHub stars value and `githubStarsIsShared` qualifies whether it represents a shared mono-repo count.
- **FR-006**: Each entry MUST support a `baseScore` float field, computed by the pipeline and readable by the app.

**Signal Pipeline**

- **FR-007**: The pipeline script MUST fetch signals from: npm Downloads API, pypistats.org, Docker Hub v2 API, Smithery registry API, GitHub REST API (repo stats + commits-by-path for mono-repo servers).
- **FR-008**: The pipeline MUST compute `baseScore` using the log-scale formula defined in the scoring model (see Key Entities).
- **FR-009**: The pipeline MUST update only the signal fields (`npmWeeklyDownloads`, `pypiMonthlyDownloads`, `dockerTotalPulls`, `smitheryUseCount`, `githubStarsIsShared`, `githubCommits90d`, `baseScore`, `signalsRefreshedAt`) in `stats.json` — all other fields, including all editorial fields in `servers.json`, MUST remain unchanged.
- **FR-010**: The pipeline MUST handle individual API failures gracefully: a failed signal fetch sets that field to null and does not abort the run.
- **FR-011**: The pipeline MUST run as a weekly GitHub Actions cron job and commit the updated `stats.json` back to the `mcp-catalog` repository.

**Swift App — Data Model**

- **FR-012**: `CatalogEntry` and `ServerMetrics` MUST be updated to decode all new schema fields, including backward-compatible decoding of the renamed `isFirstParty` → `isOfficial` field and the updated category slug values.
- **FR-013**: The app MUST scan `/Applications` and `~/Applications` at catalog-view time to detect installed apps.
- **FR-014**: The app MUST compute `displayScore = baseScore + installedAppBoost` where `installedAppBoost` is 3.0 if `relatedApp` is detected as installed, otherwise 0.

**Swift App — Sort & Display**

- **FR-015**: The catalog list MUST default to sorting by `displayScore` descending.
- **FR-016**: Entries with a non-null `editorialRank` MUST appear in a pinned section above all scored entries, sorted by `editorialRank` ascending within that section.
- **FR-017**: Each catalog list row MUST display: Official badge (if `isOfficial`), install count (npm weekly or docker pulls, whichever is non-null, formatted as "289k/wk" or "1.6M"), GitHub stars with "(repo)" qualifier if `githubStarsIsShared`.
- **FR-018**: A stale-activity indicator (amber) MUST appear on entries where `lastCommitDate` is more than 6 months before the current date.
- **FR-019**: If all signal fields are null, the entry MUST render without signal elements — no placeholder text, no error state.

### Key Entities

- **CatalogEntry** (enriched): All existing configuration fields plus `isOfficial`, `relatedApp`, `editorialRank`. The `isVerified` and `isFirstParty` fields are removed (`isFirstParty` is renamed `isOfficial`). Stored in `servers.json` in `mcp-catalog`.

- **ServerMetrics** (enriched): All existing fields (`starCount`, `lastCommitDate`, `isTrending`, etc.) plus new signal fields: `npmWeeklyDownloads`, `pypiMonthlyDownloads`, `dockerTotalPulls`, `smitheryUseCount`, `githubStarsIsShared` (bool — true when the repo is a mono-repo and star count is shared across multiple catalog entries), `githubCommits90d`, `baseScore`, `signalsRefreshedAt`. All new fields are nullable. Stored in `stats.json` in `mcp-catalog`.

- **Scoring formula**:
  ```
  primaryDist = npmWeeklyDownloads ?? (pypiMonthlyDownloads / 4) ?? 0
  baseScore =
      log10(primaryDist + 1)                        × 3.0
    + log10(dockerTotalPulls + 1)                   × 1.0
    + log10(min(smitheryUseCount, 100000) + 1)      × 1.5
    + 5.0  (if isOfficial)
    + recencyBonus  (+2 if pushed <90d, 0 if <1yr, −2 if older or unknown)
  ```

- **InstalledAppsCache**: A set of lowercase app names scanned from `/Applications` and `~/Applications` at app launch. Used only for `displayScore` computation; not persisted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user browsing the catalog can identify whether a server is official and approximately how popular it is without opening any external link — all necessary signal data is visible in the list row.
- **SC-002**: The catalog list renders correctly (no errors, no blank states) for entries with full signal data, partial signal data, and no signal data.
- **SC-003**: A server whose related desktop app is installed ranks measurably higher in the default sort order than it would without the installed-app boost.
- **SC-004**: The signal pipeline completes a full refresh of all catalog entries in under 3 minutes on a standard CI runner.
- **SC-005**: After a pipeline run, no human-authored editorial fields (`isOfficial`, `relatedApp`, `editorialRank`, `category`, `displayName`, etc.) in `servers.json` are altered.
- **SC-006**: The app correctly applies the "repo" qualifier to GitHub stars for all servers sourced from the `modelcontextprotocol/servers` mono-repo.

## Assumptions

- The signal pipeline runs as a GitHub Actions cron job with a `GITHUB_TOKEN` secret available for the commits-by-path API call.
- The app does not make any network calls to fetch signal data at runtime; all signals are bundled in the app's offline fallback catalog at build time (populated from `stats.json` on each release).
- The installed-app scan reads only app names from `/Applications` and `~/Applications`; no deeper inspection of app contents is performed.
- `editorialRank` is used sparingly (house/partner servers only); the vast majority of entries have `editorialRank: null`.
- User-configurable sort and filter controls are out of scope for this feature (v2 consideration).
- The catalog will grow to 80–100 curated entries over time; this feature must work correctly at that scale.
- A server's `relatedApp` value is the app's display name as it appears in Finder (e.g., "Notion", "Slack"), without the `.app` extension.
