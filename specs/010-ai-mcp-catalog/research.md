# Research: AI-Curated MCP Server Catalog

**Feature**: 010-ai-mcp-catalog | **Date**: 2026-05-29

---

## Decision 1: GitHub Actions Implementation Pattern for AI Enrichment Pipeline

**Decision**: Use a `run: python` step with `pip install anthropic` inside the GitHub Action, triggered by `issues: types: [labeled]` with a label guard. Use `peter-evans/create-pull-request@v8` to open the draft PR.

**Rationale**: A plain `run:` step is simpler and more maintainable than a custom Docker or JavaScript action for a single-repo workflow. The `peter-evans/create-pull-request` action is the community standard and handles branch creation, file staging, and PR opening in one step. ANTHROPIC_API_KEY is injected via GitHub secrets — never in code. A `timeout-minutes: 15` guard prevents runaway billing if Claude hangs.

**Alternatives considered**:
- Custom Docker action — unnecessary overhead; no heavy dependency set needed
- `gh pr create` — works but requires manually staging/pushing the branch first; more boilerplate for no benefit
- JavaScript action — no advantage over Python when anthropic SDK is pip-installable

**Key gotcha**: PRs created with `GITHUB_TOKEN` inside Actions do NOT trigger `pull_request` workflows. This is fine for our use case (we don't need CI on AI-generated PRs), but documented here in case that changes.

---

## Decision 2: Usage Telemetry Endpoint — Cloudflare Worker

**Decision**: A Cloudflare Worker (free tier) receives anonymous POST payloads from mcp-inator, reads the current `usage.json` from the mcp-catalog repo via GitHub Contents API (GET to fetch SHA + content), increments per-server counts, and writes back (PUT with SHA). A fine-grained GitHub PAT scoped to `Contents: read+write` on only the mcp-catalog repo is stored as an encrypted Cloudflare Worker secret.

**Rationale**: Cloudflare Workers free tier handles 100k requests/day with no credit card. The 10ms CPU limit is irrelevant since GitHub API calls are I/O (network wait time doesn't count). A fine-grained PAT stored server-side limits blast radius — the token never touches the app binary.

**Alternatives considered**:
- `repository_dispatch` from macOS app directly — eliminated. A writable repo token embedded in a distributed macOS binary is unacceptable; anyone who reverse-engineers the binary gets a token that can write to the repo.
- Supabase/PlanetScale free tier — adds a database layer; more than needed for simple count aggregation.
- GitHub Issues as data store — works at very low volume but not designed for machine-submitted data; would create issue spam.

**Key detail**: The GitHub Contents API PUT requires the current blob SHA. The Worker does a GET first to fetch the SHA, then PUTs with updated content. On a 409 conflict (two Workers writing simultaneously), retry once — at the expected volume this is rare.

---

## Decision 3: Reddit API for Sentiment Analysis

**Decision**: Use the official Reddit OAuth API (free tier, client-credentials flow for read-only access). Register a Reddit app at reddit.com/prefs/apps. Store client ID and secret as GitHub Actions secrets for the weekly sentiment workflow.

**Rationale**: Unauthenticated access is no longer viable — Reddit now throttles or blocks unidentified traffic. OAuth registration takes ~15 minutes. The free tier comfortably handles 200 weekly searches at 60–100 req/min. Total runtime: under 4 minutes for the full catalog.

**Alternatives considered**:
- Arctic Shift — a Pushshift successor with historical Reddit data; useful as a fallback for historical coverage but not needed for the weekly recent-posts use case.
- Unauthenticated JSON endpoints (reddit.com/r/sub/search.json) — unreliable as of 2025-2026; Reddit explicitly throttles unidentified traffic.

**Key constraint**: Reddit's search API caps results at 1,000 posts per subreddit — not a concern for sentiment analysis where we want only recent high-signal posts.

---

## Decision 4: Catalog JSON Schema Strategy — Extend, Don't Replace

**Decision**: The new `servers.json` schema in `rayjohnson/mcp-catalog` extends the existing `catalog.json` format used in mcp-inator. All existing fields are preserved as-is; new fields (`curatorNote`, `isFirstParty`, `alternativeTo`) are additive. The app maps between the catalog format and the existing `RegistryEntry` model using a new initializer, keeping `RegistryEntry` as the internal type throughout.

**Rationale**: The existing `RegistryEntry` model is already used throughout the UI and store layer. Replacing it would require touching `CatalogView`, `RegistryStore`, `RegistryClient`, and tests. Adding fields to the initializer is additive and backward-compatible — entries without new fields gracefully degrade to `nil`.

**Existing fields to preserve**: `id`, `displayName`, `category`, `shortDescription`, `transportType`, `command`, `args`, `url`, `envVars`, `documentationURL`, `repositoryURL`, `isVerified`, `serverKey`.

**New fields to add**: `curatorNote: String?`, `isFirstParty: Bool` (default false), `alternativeTo: String?` (serverKey of the recommended server when this is a ranked alternative).

---

## Decision 5: Two-Repo Architecture

**Decision**: The catalog lives in a new, separate public repo `rayjohnson/mcp-catalog`. The mcp-inator app repo remains separate.

**Rationale**: The catalog is a community artifact — it should be independently forkable, have its own issue templates and review process, and be adoptable by other tools without requiring knowledge of the Swift codebase. Separating concerns also means catalog PRs (from the AI pipeline) don't pollute the app's git history.

**App fetch strategy**: Three raw GitHub content URLs:
- `https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/servers.json`
- `https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/stats.json`
- `https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/trending.json`
- `https://raw.githubusercontent.com/rayjohnson/mcp-catalog/main/usage.json`

All fetched in parallel on app launch (once per session). Merged into a unified in-memory model.

---

## Decision 6: Usage Sharing — Sanitization Rules

**Decision**: The sanitization rules for the telemetry payload are:
- **Env var values**: always stripped — only key names included
- **Command paths**: if `command` matches a known package manager prefix (`npx`, `uvx`, `node`, `python`, `pip`, `docker`, `brew`) it is included as-is; otherwise replaced with `[custom-command]`
- **Args**: args that look like filesystem paths (start with `/`, `~`, `./`, `../`) are replaced with `[path]`; package names (e.g. `@scope/package`, `package-name`) are included
- **Display name / description**: user's own text, included only if user explicitly opts in per-server
- **No identifiers**: no UUID, no hostname, no username, no IP stored at any layer

**Rationale**: Users running internal tools (e.g. `/Users/ray/company-internal-mcp`) should not have those paths leaked. Package manager commands are safe to share and useful for catalog metadata. The app shows users exactly what will be sent before sending.
