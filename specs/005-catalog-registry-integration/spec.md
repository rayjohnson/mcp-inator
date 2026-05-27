# Feature Specification: Catalog Registry Integration

**Feature Branch**: `005-catalog-registry-integration`

**Created**: 2026-05-26

**Status**: Draft

## Background

The MCP registry at `registry.modelcontextprotocol.io` contains ~30,000 servers with a keyword search API (`?search=<term>`, server-side filtered). The registry returns one entry per server version; filtering to `isLatest: true` yields one clean result per unique server. The existing hand-curated `catalog.json` (18 entries) is replaced by this feature — it had stale and incorrect data (e.g. wrong env var names for home-assistant) and doesn't scale.

The approach: categories in the catalog browser become **cached registry searches**. On first launch, mcp-inator runs a background search for each category keyword, caches the `isLatest: true` results locally, and uses that cache as the offline browse experience. Users can also run live searches to find anything in the full 30,000-server registry. Env var data from the registry is always surfaced as hints, not authoritative values.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse Servers by Category (Priority: P1)

A user opens the catalog browser and sees servers organized by category (Code & Dev, Data, Communication, etc.). The listings come from the registry, not a hand-curated file, so they reflect real-world available servers. On first launch, categories are populated in the background; on subsequent launches, the cached results are shown immediately.

**Why this priority**: This is the replacement for the broken bundled catalog — the default browse experience that every user hits first. It must work before anything else.

**Independent Test**: Delete the local cache, launch the app with network access, open the catalog browser. Verify categories populate with registry-sourced servers within a reasonable time. Relaunch the app offline — verify the same categories are shown from cache.

**Acceptance Scenarios**:

1. **Given** the app is launched for the first time with network access, **When** the user opens the catalog browser, **Then** category listings are populated from the registry in the background, with a loading state shown until ready.
2. **Given** category data has been cached from a previous launch, **When** the user opens the catalog browser on a subsequent launch, **Then** cached results are shown immediately without waiting for a network request.
3. **Given** cached category data exists, **When** the app launches with network access, **Then** the cache is refreshed in the background and the UI updates if results have changed.
4. **Given** the app is launched with no network and no cache (true first launch offline), **When** the user opens the catalog browser, **Then** a clear message explains that categories will be available after connecting to the internet once.

---

### User Story 2 - Search the Full Registry (Priority: P2)

A user wants a server that isn't in any of the browseable categories. They type a keyword into the search bar and see live results from the full registry — beyond what's cached locally.

**Why this priority**: Categories cover common cases but not everything. Live search unlocks the full 30,000-server registry for any keyword.

**Independent Test**: Type a niche keyword (e.g., "obsidian") into the catalog search bar. Verify live registry results appear that go beyond the cached category content.

**Acceptance Scenarios**:

1. **Given** the user types in the catalog search bar, **When** they pause typing, **Then** live registry results appear, filtered to latest-version entries only.
2. **Given** live search results are shown, **When** the user selects a result, **Then** they can add it to their server library using the same flow as browsed catalog entries.
3. **Given** the registry is unreachable during a search, **When** the search completes, **Then** only locally-cached matches are shown, with a notice that live results are unavailable.
4. **Given** the registry search returns no results, **When** the user views the state, **Then** a clear "no results found" message is shown rather than a blank screen.

---

### User Story 3 - Use the App Offline (Priority: P3)

A user opens mcp-inator without network access. They can still browse categories and search within cached content from their last online session.

**Why this priority**: Offline usability must not completely break. The cache is the safety net.

**Independent Test**: After at least one successful online launch, disable network access and relaunch. Verify categories are visible, local search works, and the UI clearly indicates live search is unavailable.

**Acceptance Scenarios**:

1. **Given** the app has previously populated its cache, **When** launched without network access, **Then** all categories show their cached server listings.
2. **Given** no network access, **When** the user searches, **Then** the search filters cached content locally and a notice indicates live registry search is unavailable.
3. **Given** no network and no prior cache, **When** the user opens the catalog browser, **Then** a helpful message is shown explaining that the catalog requires one initial online session to populate.

---

### User Story 4 - See Env Var Suggestions as Hints (Priority: P4)

A user selects a server and sees suggested environment variable names pre-populated in the configuration form, clearly marked as hints to verify against the package's own documentation.

**Why this priority**: Prevents the category of bug that prompted this whole feature (wrong env var names silently misconfiguring servers). Lower priority than the browse/search experience but essential for trust.

**Independent Test**: Select any server entry that has env var suggestions. Verify each field is visually marked as a hint with copy like "suggested — verify with package docs".

**Acceptance Scenarios**:

1. **Given** a server entry has env var suggestions, **When** a user views its detail or starts adding it, **Then** suggested variable names are pre-populated and visually marked as hints.
2. **Given** env var hints are shown, **When** a user reads the UI, **Then** clear copy (e.g., "suggested — verify with package docs") accompanies each suggestion.
3. **Given** a user edits, clears, or ignores a hint value, **When** they save the configuration, **Then** their actual input is saved — hints are purely cosmetic.
4. **Given** a server entry has no env var data, **When** a user views it, **Then** no env var section is shown — no empty or placeholder fields.

---

### Edge Cases

- What happens when a category search returns zero results from the registry?
- What if the cache is partially populated (some categories loaded, some not) when the user goes offline?
- What if a registry search returns a server whose derived launch command conflicts with an existing user-configured server?
- What if a registry result has no package data and no remote URL (nothing actionable)?
- What happens if the user types and clears the search bar rapidly — are stale in-flight results discarded?
- What if a registry entry has env var data with blank or malformed variable names?

## Requirements *(mandatory)*

### Functional Requirements

**Category Browse**

- **FR-001**: The catalog browser MUST organize servers into categories populated from cached registry searches, replacing the static bundled `catalog.json`.
- **FR-002**: On first launch with network access, the app MUST populate the category cache by running a background search per category using defined keyword mappings.
- **FR-003**: On subsequent launches, cached category results MUST be shown immediately while a background refresh runs if network is available.
- **FR-004**: Category search results MUST be filtered to `isLatest: true` entries only, showing one result per unique server.
- **FR-005**: If the app has never been online (no cache exists), the catalog browser MUST show a clear message explaining that one online session is needed to populate the catalog.

**Live Search**

- **FR-006**: The catalog browser MUST include a search bar that queries the MCP registry live when network access is available.
- **FR-007**: Live search results MUST be filtered to `isLatest: true` entries, deduplicated by server name.
- **FR-008**: Live search MUST be triggered automatically as the user types (debounced), not requiring an explicit submit.
- **FR-009**: When the registry is unreachable, search MUST fall back to filtering cached content locally, with a visible notice.

**Adding Servers**

- **FR-010**: Any server from browse or search results MUST be addable to the user's library with the same flow regardless of source.
- **FR-011**: For stdio servers, the launch command and args MUST be derived from package type: npm → `npx -y <identifier>`, pypi → `uvx <identifier>`, oci → `docker run <identifier>`.
- **FR-012**: For HTTP/SSE servers, the URL MUST be taken directly from the registry entry's remote URL field. Request headers (e.g., bearer tokens) are surfaced as hints alongside env var suggestions.
- **FR-013**: Registry results with neither a derivable stdio command nor a remote URL MUST be excluded from results.

**Env Var Hints**

- **FR-014**: Env var suggestions from registry data MUST be visually distinguished from user-entered values.
- **FR-015**: Each env var suggestion MUST be accompanied by inline copy indicating it is a hint to verify, not an authoritative value.
- **FR-016**: The hint treatment MUST be cosmetic only — it MUST NOT prevent users from editing, clearing, or saving any value.
- **FR-017**: If a server entry has no env var data, the configuration UI MUST NOT display empty hint fields.

### Key Entities

- **Category Cache**: Locally stored results of a registry search per category, keyed by category name. Populated on first launch, refreshed in the background on subsequent launches.
- **Category Keyword Map**: The defined mapping from category name to registry search term(s) used to populate that category's cache (e.g., "Data" → searches for "postgres", "sqlite", "database").
- **Registry Search Result**: A live result from the MCP registry, filtered to `isLatest: true`. Includes name, description, package type/identifier or remote URL, and optionally env var/header suggestions.
- **Derived Launch Config**: The command and args computed from a registry result's package type and identifier (e.g., npm `@foo/mcp` → `npx -y @foo/mcp`).
- **Env Var Hint**: A suggested environment variable name from registry data, presented as a starting point to verify — not a guaranteed-correct value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On first launch with network access, all category listings are populated within 10 seconds without any user action.
- **SC-002**: On subsequent launches, category listings are visible immediately (from cache) — zero wait time for the default browse experience.
- **SC-003**: Users who have launched the app at least once can browse all categories while offline — no empty category states for returning users.
- **SC-004**: Live search results appear within 3 seconds of the user pausing their input.
- **SC-005**: 100% of env var suggestion fields are accompanied by visible hint copy — no suggestions presented without the "verify with docs" indicator.
- **SC-006**: App launch time is not measurably affected — all registry activity runs in the background.

## Assumptions

- The MCP registry API at `registry.modelcontextprotocol.io` supports keyword search via `?search=<term>` (confirmed by probing). The `isLatest: true` flag in `_meta` reliably identifies the current version of each server (confirmed: "postgres" returns 35 entries, 11 with `isLatest: true`).
- The registry API does not require authentication for read access.
- The category keyword map (e.g., "Data" → "postgres", "sqlite") is defined at build time and updated with app releases. Choosing good keywords is an editorial decision, not a technical one.
- Launch commands can be reliably derived from package type: npm → `npx -y`, pypi → `uvx`, oci → `docker run`. Servers requiring non-standard invocations are out of scope.
- HTTP/SSE servers from the registry are in scope. The app already supports HTTP transport with request headers.
- The registry may return env var data that is incorrect — the hint UI treatment is the mitigation, not server-side validation.
- The static `catalog.json` file and the `CatalogStore` bundled-load path are removed as part of this feature. The category cache replaces them entirely.
- Cache invalidation strategy (TTL, manual refresh) is a planning decision — the spec does not prescribe it.
