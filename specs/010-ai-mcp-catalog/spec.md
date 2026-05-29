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

### User Story 5 — Anonymous Usage Data Sharing (Priority: P2)

A user who has been running several MCP servers for a few weeks sees a prompt in mcp-inator asking if they'd like to contribute their usage data to improve the catalog. They tap "Review what I'd share" and see a clear list: server keys, commands, which env var names (not values) are configured, and — optionally — any descriptions they've written for their own servers. They uncheck one internal server they don't want to share, then submit. Their anonymized data joins a pool that makes the catalog's popularity rankings reflect real-world usage rather than GitHub stars.

Over time, as more users contribute, the catalog gains a "used by N mcp-inator users" count per server — a signal no other registry has.

**Why this priority**: This is the highest-quality popularity signal available and gets better with every user who opts in. It also creates a feedback loop where users feel invested in the catalog's quality. Ranked P2 because it requires the catalog infrastructure (US1/US2) to exist first and introduces privacy/consent complexity that warrants a separate implementation pass.

**Independent Test**: Enable sharing in settings, open the sharing review screen, verify the payload shown matches the sanitized format (no env var values, no internal paths, per-server opt-out works). Submit and verify the aggregation endpoint receives valid data. Verify the resulting `usage.json` in the catalog repo reflects the contributed server keys with incremented counts.

**Acceptance Scenarios**:

1. **Given** a user has never been asked about sharing, **When** they have used mcp-inator for at least 7 days with at least one enabled server, **Then** a non-intrusive prompt appears offering to let them review and share usage data — opt-in only, never automatic.
2. **Given** a user opens the sharing review screen, **When** they view it, **Then** they see: each server's key and command, the list of env var names configured (no values), whether the server is currently enabled, and any description they've written — with a per-server toggle to exclude individual entries.
3. **Given** a user submits their usage data, **When** the payload is sent, **Then** it contains no env var values, no file system paths that could identify the machine, no user identifiers, and no IP address is stored by the receiving endpoint.
4. **Given** a user has opted in to sharing, **When** they open Settings, **Then** they can withdraw participation at any time, which prevents any future sharing and removes their identifier from the sharing pool.
5. **Given** usage data has been received from multiple users, **When** the weekly aggregation job runs, **Then** `usage.json` in the catalog repo is updated with per-server usage counts that the app can display as "used by N mcp-inator users."
6. **Given** a server in a user's library is not in the catalog, **When** the user shares usage data, **Then** that server's data is included in the payload and flagged as a potential new catalog candidate for the AI enrichment pipeline to process.

---

### Edge Cases

- What if the GitHub API is rate-limited during the submission pipeline? Pipeline retries up to 3 times with backoff; if still failing, the PR opens with a note that stats could not be fetched.
- What if a submitted URL is not a GitHub repo (e.g. an npm page)? The pipeline comments on the issue asking for a GitHub URL and closes it without creating a PR.
- What if `servers.json` is malformed after a bad merge? The app falls back to the bundled catalog silently.
- What if a server changes its install command between refreshes? The drift PR flags the change for curator review.
- What if the Reddit API is unavailable during the weekly run? The sentiment job skips gracefully; existing `trending.json` data is preserved unchanged.
- What if a user's server list contains commands with internal paths (e.g. `/Users/ray/internal-tool`)? The sharing payload replaces any filesystem path that isn't a well-known package manager command with `[redacted]` before display and before transmission.
- What if the usage data aggregation endpoint is unavailable? The app queues the payload locally and retries on the next app launch; after 3 failed attempts it silently drops the payload rather than showing an error.

---

## Requirements

### Functional Requirements

**Catalog Repository**

- **FR-001**: The catalog MUST be stored as a public GitHub repository containing two human-readable JSON files: `servers.json` (curated entries, human-reviewed) and `stats.json` (all computed per-server metrics: GitHub stats, Reddit sentiment, and usage counts — auto-updated weekly).
- **FR-002**: Submissions MUST be accepted via a structured GitHub Issue template requiring at minimum a GitHub repository URL.
- **FR-003**: The AI enrichment pipeline MUST produce a complete catalog entry from a GitHub repo URL, populating: display name, description, curator note, command, args, required args, env vars (name / description / required / sensitive), transport type, first-party flag, documentation URL, repository URL, and category.
- **FR-004**: When a submission is for a service already in the catalog, the pipeline MUST produce a comparison comment on the PR (stars, maintenance recency, first-party status) rather than silently replacing the existing entry.
- **FR-005**: Every valid submission MUST result in a draft PR; no entry may enter `servers.json` without human review and merge.
- **FR-006**: Duplicate submissions (same repo URL already cataloged) MUST be detected and rejected with an explanatory issue comment; no PR is created.
- **FR-007**: The weekly refresh MUST update `stats.json` with current GitHub star count, fork count, last commit date, and open issue count for every catalog entry.
- **FR-008**: The weekly refresh MUST detect significant drift (archived repos, new or removed required env vars) and open PRs flagging affected entries.
- **FR-009**: The weekly Reddit sentiment job MUST search a curated list of subreddits for each server by name, summarize community sentiment in one sentence, assign a trending score (0–100), and set the `isTrending` flag in `stats.json`. The initial subreddit list is r/ClaudeAI, r/ClaudeCode, r/MCPservers. The active list MUST be stored in `config.json` in the catalog repo. On a monthly cadence the sentiment job MUST ask Claude to evaluate the current subreddit list quality and discover emerging MCP communities, updating `config.json` if better sources are found — no human intervention required.

**mcp-inator App**

- **FR-010**: The app MUST fetch live catalog data from the catalog repository's raw file URLs, merging `servers.json` and `stats.json` into a unified display model.
- **FR-011**: The app MUST fall back to a bundled catalog when the live fetch fails, with no visible error to the user.
- **FR-012**: Each catalog entry MUST display: display name, description, curator note, first-party badge (when applicable), GitHub star count, last-commit recency, required env vars with descriptions, and a documentation link.
- **FR-013**: Servers flagged as `isTrending: true` in `stats.json` MUST appear in a dedicated "Trending" section at the top of the catalog. The weekly sentiment job is responsible for setting this flag based on its analysis of score distributions — the app applies the flag as-is with no threshold logic of its own.
- **FR-014**: When multiple servers exist for the same service, the recommended pick MUST be shown at full size in the catalog list. Alternatives (entries whose `alternativeTo` points to the recommended pick's `id`) MUST be collapsed beneath it behind a disclosure control (e.g. "2 alternatives"). Expanding the disclosure reveals the alternatives inline. Only the recommended pick appears at top level by default.
- **FR-015**: The catalog MUST refresh live data at most once per app session and cache the result locally for offline use.

**Usage Data Sharing (mcp-inator App)**

- **FR-016**: The app MUST present the sharing opt-in as an explicit, reviewable prompt — never as a pre-checked preference or background upload. Sharing MUST be off by default.
- **FR-017**: Before any data is transmitted, the user MUST be shown a review screen displaying the exact sanitized payload, with a per-server toggle to exclude individual entries.
- **FR-018**: The sharing payload MUST exclude: all env var values, any filesystem paths not matching a known package manager pattern (replaced with `[redacted]`), any device identifiers, and any usernames or account information.
- **FR-019**: The sharing payload MUST include for each opted-in server: server key, command, sanitized args, transport type, enabled/disabled state, env var key names (no values), and optionally the user's own description if they choose to include it.
- **FR-020**: Users MUST be able to withdraw from sharing at any time via Settings, which prevents future submissions.
- **FR-021**: When a user's library contains a server not present in the catalog, that server's sanitized data MUST be included in the sharing payload and flagged as a potential new catalog entry for AI enrichment.
- **FR-022**: The Cloudflare Worker MUST accumulate received usage reports into an internal `usage.json` file (not fetched by the app). The weekly refresh job MUST fold per-server usage counts from `usage.json` into `stats.json`, which the app downloads and displays as "used by N mcp-inator users."
- **FR-023**: The aggregation endpoint MUST NOT store IP addresses or any information that could re-identify a contributor.

### Key Entities

- **CatalogEntry**: A curated MCP server record. Key fields: id, displayName, shortDescription, curatorNote, command, args, envVars, requiredArgs, transportType, isFirstParty, documentationURL, repositoryURL, category, alternativeTo (optional — links to the recommended entry when this is a ranked alternative).
- **EnvVarDefinition**: name, description, isRequired, isSensitive.
- **ServerMetrics**: All computed per-server signals, published in `stats.json`. Fields: serverKey, repositoryURL, starCount, forkCount, lastCommitDate, openIssueCount, isArchived, githubFetchedAt, trendingScore (0–100), sentimentSummary, mentionCount, sentimentComputedAt, userCount, enabledCount, weeklyActiveCount, usageAggregatedAt.
- **UsageReport**: An anonymized snapshot of one user's opted-in server library. Fields: reportedAt, servers (array of sanitized server entries). Never stored with any user identifier beyond a random session token that resets on each submission. Accumulated in the catalog repo's internal `usage.json` by the Cloudflare Worker; folded into `stats.json` by the weekly refresh job.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: A user can find, evaluate, and add an MCP server from the catalog in under 2 minutes without visiting any external page to understand what env vars are required.
- **SC-002**: 100% of catalog entries have all required fields populated — no blank descriptions, no missing env var lists.
- **SC-003**: A community submission results in a reviewable PR within 10 minutes of the issue being opened.
- **SC-004**: The weekly refresh detects and flags archived or significantly drifted entries within one week of the change occurring on GitHub.
- **SC-005**: The catalog contains at least 50 high-quality entries within 60 days of launch, without the curator manually typing metadata for any of them.
- **SC-006**: Total infrastructure cost remains $0 in hosting and under $5/month in AI API costs at steady state.
- **SC-007**: Usage sharing opt-in rate reaches at least 20% of active users within 90 days of the feature launching, as measured by non-zero entries in `usage.json`.
- **SC-008**: Within 30 days of usage sharing launch, at least 5 servers not previously in the catalog are discovered via user reports and added through the AI enrichment pipeline.

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
- Usage data sharing requires a minimal serverless endpoint (e.g. a Cloudflare Worker on the free tier) to receive payloads and write aggregated counts to the catalog repo via the GitHub API. This is the only infrastructure required and has no maintenance burden or ongoing cost.
- The sharing prompt is shown no earlier than 7 days after first launch and only when the user has at least one enabled server — avoiding prompting users who haven't meaningfully used the app.
- "Used by N users" counts are aggregated weekly; they reflect the number of distinct contributors who included a server in their most recent report, not a cumulative all-time count.
