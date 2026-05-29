# Feature Specification: AI-Curated MCP Server Catalog with Community Submissions

**Feature Branch**: `010-ai-mcp-catalog`

**Created**: 2026-05-28

**Status**: Draft

## User Scenarios & Testing

### User Story 1 — Browse a Rich, Curated Catalog in mcp-inator (Priority: P1)

A user opens the mcp-inator catalog tab looking for an MCP server for a service they use (e.g. Slack, Linear, Stripe). Instead of an undifferentiated list, they see curated recommendations — one per service — with a plain-English description, a curator note explaining why this server was chosen over alternatives, the exact env vars they'll need, and trust signals like "first-party" (made by the service's own team) and GitHub star count. They add the server with confidence, having never had to visit an external page.

**Why this priority**: This is the core user-facing value. Without a richer catalog experience, everything else is infrastructure with no visible payoff.

**Independent Test**: Manually populate `servers.json` in the catalog repo with 10 enriched entries. Update mcp-inator to fetch from that URL and render the new fields. Verify a user can browse, read curator notes, see env var requirements, and add a server — end to end — without building any AI pipeline.

**Acceptance Scenarios**:

1. **Given** the catalog is open, **When** a user views any server entry, **Then** they see: display name, one-sentence description, curator note, required env vars with descriptions, first-party badge (if applicable), GitHub star count, last-commit recency, and a documentation link.
2. **Given** multiple servers exist for the same service, **When** a user views that category, **Then** one is shown as the recommended pick and alternatives are listed below it with brief comparison notes.
3. **Given** no internet connection, **When** the catalog tab is opened, **Then** a bundled fallback catalog is displayed without error.
4. **Given** a server has a trending score above the threshold, **When** the catalog loads, **Then** it appears in a "Trending" section at the top.

---

### User Story 2 — Submit a New Server via GitHub Issue (Priority: P1)

A community member finds an MCP server they love and wants to add it to the catalog. They open a GitHub Issue in the catalog repo, paste the server's GitHub URL, optionally add a sentence about why they like it, and submit. Within minutes an AI pipeline produces a fully-populated draft catalog entry — description, env vars, command, first-party flag, curator note — and opens a PR. The curator reads it, tweaks a sentence if needed, and merges. The server appears in the app on the next catalog refresh.

**Why this priority**: The submission pipeline is what keeps the catalog growing without the curator doing data entry. Without it, the catalog stagnates.

**Independent Test**: Open a GitHub Issue with a real MCP server's repo URL. Verify the pipeline fires, a PR opens within 10 minutes, the PR contains a valid `servers.json` entry with all required fields populated from the repo's actual README content.

**Acceptance Scenarios**:

1. **Given** a submitter opens an issue using the submission template with a valid GitHub repo URL, **When** the pipeline runs, **Then** a PR is opened containing a complete catalog entry with all required fields populated.
2. **Given** a submission is for a service already in the catalog, **When** the pipeline runs, **Then** the PR includes a comparison comment (stars, maintenance recency, first-party status) without automatically replacing the existing entry.
3. **Given** a submitted repo has a missing or unreadable README, **When** the pipeline runs, **Then** a PR is still opened with fields that could be extracted and remaining fields flagged for human completion.
4. **Given** a submission duplicates an existing catalog entry (same repo URL), **When** the pipeline runs, **Then** no PR is created and a comment explains the server is already listed.

---

### User Story 3 — Catalog Stays Fresh Automatically (Priority: P2)

A server in the catalog has been archived on GitHub. Another has added required env vars not in its catalog entry. A third has exploded in popularity. Without anyone doing anything, the weekly pipeline detects these changes, updates star counts and trending scores, and opens PRs for significant drift — so the curator reviews and merges rather than discovering stale data by accident.

**Why this priority**: A catalog that rots loses trust. Automated freshness separates this from every other static MCP server list.

**Independent Test**: Alter a test catalog entry to have a wrong star count and a missing env var. Run the weekly refresh Action manually. Verify it opens a PR with corrected data and flags the missing env var.

**Acceptance Scenarios**:

1. **Given** a catalog entry's GitHub repo has been archived or deleted, **When** the weekly refresh runs, **Then** a PR is opened flagging the entry for removal or replacement.
2. **Given** a catalog entry is missing an env var documented in the repo's current README, **When** the weekly refresh runs, **Then** a PR is opened with the updated env var list.
3. **Given** any catalog server's star count has changed, **When** the weekly refresh runs, **Then** `stats.json` is updated automatically without requiring a PR.
4. **Given** a server's star count grew more than 20% in the past week, **When** the refresh runs, **Then** its trending score increases accordingly.

---

### User Story 4 — Reddit Sentiment Signals (Priority: P3)

A server generating buzz on Reddit appears with a one-line community sentiment summary in the catalog — e.g. "Widely praised for easy setup; occasional auth issues reported on older versions." Users make better decisions because they see what real people say, not just star counts.

**Why this priority**: Useful signal but dependent on the freshness pipeline (US3) being in place first, and on Reddit API access remaining stable.

**Independent Test**: Run the Reddit sentiment Action against 5 catalog entries with known Reddit discussion. Verify `trending.json` contains a non-empty sentiment string and score for each, and the app displays the sentiment string on the detail view.

**Acceptance Scenarios**:

1. **Given** a server has been mentioned in relevant subreddits in the past 30 days, **When** the weekly sentiment job runs, **Then** a one-line summary and trending score (0–100) are written to `trending.json`.
2. **Given** a server has no recent Reddit mentions, **When** the job runs, **Then** no sentiment string is shown in the app (field is absent, not "No mentions found").
3. **Given** `trending.json` is available, **When** the app loads, **Then** servers with a score above 70 appear in the "Trending" section.

---

### Edge Cases

- What if the GitHub API is rate-limited during the submission pipeline? Pipeline retries up to 3 times with backoff; if still failing, the PR opens with a note that stats could not be fetched.
- What if a submitted URL is not a GitHub repo (e.g. an npm page)? The pipeline comments on the issue asking for a GitHub URL and closes it without creating a PR.
- What if `servers.json` is malformed after a bad merge? The app falls back to the bundled catalog silently.
- What if a server changes its install command between refreshes? The drift PR flags the change for curator review.
- What if the Reddit API is unavailable during the weekly run? The sentiment job skips gracefully; existing `trending.json` data is preserved unchanged.

---

## Requirements

### Functional Requirements

**Catalog Repository**

- **FR-001**: The catalog MUST be stored as a public GitHub repository containing human-reviewable JSON files: `servers.json` (curated entries), `stats.json` (GitHub metrics), `trending.json` (Reddit signals).
- **FR-002**: Submissions MUST be accepted via a structured GitHub Issue template requiring at minimum a GitHub repository URL.
- **FR-003**: The AI enrichment pipeline MUST produce a complete catalog entry from a GitHub repo URL, populating: display name, description, curator note, command, args, env vars (name / description / required / sensitive), transport type, first-party flag, documentation URL, repository URL, and category.
- **FR-004**: When a submission is for a service already in the catalog, the pipeline MUST produce a comparison comment on the PR (stars, maintenance recency, first-party status) rather than silently replacing the existing entry.
- **FR-005**: Every valid submission MUST result in a draft PR; no entry may enter `servers.json` without human review and merge.
- **FR-006**: Duplicate submissions (same repo URL already cataloged) MUST be detected and rejected with an explanatory issue comment; no PR is created.
- **FR-007**: The weekly refresh MUST update `stats.json` with current GitHub star count, fork count, last commit date, and open issue count for every catalog entry.
- **FR-008**: The weekly refresh MUST detect significant drift (archived repos, new or removed required env vars) and open PRs flagging affected entries.
- **FR-009**: The weekly Reddit sentiment job MUST search relevant subreddits for each server by name, summarize community sentiment in one sentence, and assign a trending score (0–100) written to `trending.json`.

**mcp-inator App**

- **FR-010**: The app MUST fetch live catalog data from the catalog repository's raw file URLs, merging `servers.json`, `stats.json`, and `trending.json` into a unified display model.
- **FR-011**: The app MUST fall back to a bundled catalog when the live fetch fails, with no visible error to the user.
- **FR-012**: Each catalog entry MUST display: display name, description, curator note, first-party badge (when applicable), GitHub star count, last-commit recency, required env vars with descriptions, and a documentation link.
- **FR-013**: Servers with a trending score above a configurable threshold MUST appear in a dedicated "Trending" section at the top of the catalog.
- **FR-014**: When multiple servers exist for the same service, one MUST be shown as the recommended pick with alternatives listed below it.
- **FR-015**: The catalog MUST refresh live data at most once per app session and cache the result locally for offline use.

### Key Entities

- **CatalogEntry**: A curated MCP server record. Key fields: id, displayName, shortDescription, curatorNote, command, args, envVars, requiredArgs, transportType, isFirstParty, documentationURL, repositoryURL, category, alternativeTo (optional — links to the recommended entry when this is a ranked alternative).
- **EnvVarDefinition**: name, description, isRequired, isSensitive.
- **ServerStats**: repositoryURL, starCount, forkCount, lastCommitDate, openIssueCount, fetchedAt.
- **TrendingEntry**: repositoryURL, trendingScore (0–100), sentimentSummary, mentionCount, periodDays, computedAt.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: A user can find, evaluate, and add an MCP server from the catalog in under 2 minutes without visiting any external page to understand what env vars are required.
- **SC-002**: 100% of catalog entries have all required fields populated — no blank descriptions, no missing env var lists.
- **SC-003**: A community submission results in a reviewable PR within 10 minutes of the issue being opened.
- **SC-004**: The weekly refresh detects and flags archived or significantly drifted entries within 24 hours of the change occurring on GitHub.
- **SC-005**: The catalog contains at least 50 high-quality entries within 60 days of launch, without the curator manually typing metadata for any of them.
- **SC-006**: Total infrastructure cost remains $0 in hosting and under $5/month in AI API costs at steady state.

---

## Assumptions

- The catalog repository (`rayjohnson/mcp-catalog`) is a separate public GitHub repo from the mcp-inator app repo, created before implementation begins.
- GitHub Actions free tier (2,000 minutes/month for public repos) is sufficient for the submission pipeline and weekly jobs at expected volume.
- The Claude API is used for AI enrichment; a GitHub Actions secret stores the API key. Cost per submission is estimated at $0.03–$0.10 depending on repo size.
- Reddit's public API (free tier) is used for sentiment; rate limits are manageable for weekly batch processing of up to 200 entries.
- v1 supports GitHub-hosted repos only; servers on GitLab, Bitbucket, or distributed via npm/PyPI without a GitHub repo are out of scope.
- The curator (repo owner) reviews and merges all PRs; no automated merging occurs.
- The existing mcp-inator catalog data model is extended rather than replaced; new fields are additive and the app gracefully handles entries missing optional fields.
- The bundled fallback catalog is updated manually with each mcp-inator app release; it is not auto-synced from the live catalog repo.
