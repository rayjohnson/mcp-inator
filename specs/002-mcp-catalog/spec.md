# Feature Specification: MCP Server Catalog

**Feature Branch**: `002-mcp-catalog`

**Created**: 2026-05-25

**Status**: Draft

**Input**: User description: "Pre-defined MCP server catalog: browse a curated list of known community MCP servers, preview their details (command, args, description, links), and add them to the mcp-inator library with one click. No agent writes happen at add time — the catalog is a discovery and quick-add mechanism for the config library."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse Catalog and Add a Server (Priority: P1)

A user who wants to add the GitHub MCP server doesn't know the exact command or package name. They open the catalog tab in mcp-inator, see a curated list of popular MCP servers organized by category, find "GitHub" under "Code & Development", tap it to see its description and default configuration, and add it to their library with one tap. The add form opens pre-filled with the correct command and arguments — they only need to provide their GitHub token and save.

**Why this priority**: This is the complete core value of the feature. Without the ability to browse, preview, and add a server, nothing else has meaning.

**Independent Test**: Open mcp-inator with an empty library → open the Catalog tab → locate "GitHub MCP" under "Code & Development" → tap to preview → tap "Add to Library" → confirm the add form opens with `command: npx` and `args: ["@modelcontextprotocol/server-github"]` pre-filled → fill in `GITHUB_TOKEN` → save → entry appears in the library. No agent config files should be modified during this entire flow.

**Acceptance Scenarios**:

1. **Given** an empty library and a user on the Catalog tab, **When** the user taps any catalog entry, **Then** a detail view opens showing the server's name, description, default command, default arguments, required environment variables with descriptions, and at least one documentation link.

2. **Given** a catalog detail view is open, **When** the user taps "Add to Library", **Then** the Add/Edit Config form opens pre-populated with all known fields from the catalog entry, and no agent files are written.

3. **Given** a catalog entry's form is pre-populated, **When** the user edits any field and saves, **Then** the library stores the user's edited version, not the original catalog defaults.

4. **Given** a catalog entry is already in the user's library (same server key), **When** the user views that catalog entry, **Then** a visual indicator shows "Already in library" and the "Add to Library" button is replaced with "Edit in Library".

---

### User Story 2 - Search and Filter the Catalog (Priority: P1)

A user who has heard about "Obsidian MCP" but can't find it by scrolling opens the search field in the catalog, types "obsidian", and immediately sees the matching entry. A user who wants to discover available data tools filters by the "Data & Analytics" category and browses the results.

**Why this priority**: P1 because the catalog is only useful if entries can be found quickly. A list of 50+ servers without search becomes a scrollable wall. Search is inseparable from the browse experience.

**Independent Test**: Open the Catalog tab with a bundled catalog of at least 10 entries across 3 categories → type "obsidian" in the search field → verify only matching entries appear → clear search → select "Data & Analytics" from category filter → verify only entries in that category appear → select "All" → verify full list returns.

**Acceptance Scenarios**:

1. **Given** the catalog is open, **When** the user types in the search field, **Then** the list filters in real-time to show only entries whose name or description contains the search text, with results appearing as each character is typed.

2. **Given** the catalog is open, **When** the user selects a category from the filter, **Then** only entries in that category are shown, and the count of visible entries updates.

3. **Given** a search yields no results, **When** the list is empty, **Then** an empty state message tells the user no servers matched their search and offers to clear the filter.

---

### User Story 3 - Catalog Data Stays Current (Priority: P2)

A user who installed mcp-inator three months ago wants to know if new MCP servers have been added to the catalog since then. They find a "Check for Updates" action in the catalog, tap it, and the catalog refreshes with newer entries while the app remains functional throughout.

**Why this priority**: P2 because the bundled catalog provides value immediately; refresh improves long-term utility. A stale catalog is annoying but not a blocker.

**Independent Test**: Launch mcp-inator with a bundled catalog → trigger a catalog refresh while connected to the internet → confirm the catalog updates without the app restarting and without any library data being modified → disconnect from the internet → trigger refresh again → confirm a non-blocking error appears and the existing catalog is unchanged.

**Acceptance Scenarios**:

1. **Given** the app has an internet connection, **When** the user triggers a catalog refresh, **Then** the catalog updates to include new entries, existing entries may be updated, removed entries disappear, and the user's library is not modified.

2. **Given** a catalog refresh fails (no internet or server unavailable), **When** the failure occurs, **Then** the existing catalog remains intact, a non-blocking message explains the failure, and the user can continue using the local catalog.

3. **Given** a refresh completes successfully, **When** it finishes, **Then** the UI indicates when the catalog was last refreshed (e.g., "Updated just now" or a timestamp).

---

### Edge Cases

- What happens if a catalog entry's command or package name changes between catalog versions? The library retains the user's previously saved values unchanged; only new adds use the updated catalog defaults.
- What if the user adds a catalog entry, edits it, then sees it again in the catalog — are the catalog defaults shown or the user's version? The catalog always shows its own defaults; the "Already in library" indicator links to the user's version.
- What if a catalog entry requires environment variables the user cannot provide (e.g., an enterprise-only token)? The user can still add the entry with a placeholder value and edit it later.
- What if the catalog is empty after a failed refresh? The last successfully loaded catalog is shown; the app never presents an empty catalog due to a transient network failure.
- What if two catalog entries have the same server key? Catalog data must have unique server keys; this is a data integrity constraint on the catalog source, not a user-facing scenario.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The catalog MUST be accessible and fully usable without an internet connection using bundled data shipped with the app.
- **FR-002**: Each catalog entry MUST display: display name, category, short description, command, default arguments, a list of required environment variables (each with a name, human-readable description, and whether it is sensitive), and at least one link (documentation or source repository).
- **FR-003**: Users MUST be able to add any catalog entry to their config library in a single tap, with all known fields pre-populated in the Add/Edit Config form.
- **FR-004**: Adding a catalog entry MUST NOT write to any agent config file; it only creates a record in the mcp-inator library.
- **FR-005**: Users MUST be able to search catalog entries by name and description. Results MUST update as the user types with no perceptible delay.
- **FR-006**: Users MUST be able to filter catalog entries by category. A special "All" category shows the unfiltered list.
- **FR-007**: Each catalog entry MUST display a visual indicator if a library config with the same server key already exists.
- **FR-008**: When a catalog entry is already in the library, the "Add to Library" action MUST be replaced with an "Edit in Library" action that opens the existing config for editing.
- **FR-009**: Users MUST be able to trigger a manual catalog refresh. During a refresh, the existing catalog remains visible and usable.
- **FR-010**: A failed catalog refresh MUST leave the existing catalog intact and display a non-blocking error message. The app MUST NOT become unusable due to a failed refresh.
- **FR-011**: The catalog MUST record when it was last successfully refreshed and display this to the user.
- **FR-012**: Catalog entries that require sensitive environment variables MUST follow the same sensitivity defaults as the config library (values matching the `${VAR_NAME}` reference pattern are not sensitive; others are).
- **FR-013**: The empty catalog state (no bundled data, pre-first-launch) MUST display a helpful message rather than a blank screen.

### Key Entities

- **CatalogEntry**: Represents one known MCP server in the catalog. Key attributes: unique identifier, display name, category, short description (one to two sentences), command, default arguments list, required environment variable definitions (each with key name, human-readable description of what the value should be, and whether the value is sensitive), official documentation URL, source repository URL (optional), verification status (community-submitted vs. curated/verified), version the entry was added or last updated.
- **CatalogCategory**: A grouping for catalog entries. Examples: Code & Development, Productivity, Data & Analytics, Communication, Infrastructure. Each entry belongs to exactly one category.
- **CatalogMetadata**: Tracks the catalog as a whole: when it was bundled (app build time), when it was last successfully refreshed from the remote source, the version or etag of the remote catalog.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user who knows a server's name can find and add it to their library in under 30 seconds from opening the catalog tab.
- **SC-002**: The catalog view opens and displays entries within 1 second of navigation, even without an internet connection.
- **SC-003**: Search results appear in under 100 milliseconds of each keystroke with no visible lag.
- **SC-004**: 100% of "Add to Library" actions from the catalog produce a pre-populated form where command and default arguments are filled in correctly and match the catalog entry's defined values.
- **SC-005**: A catalog refresh that succeeds completes without requiring the user to restart the app or re-navigate to the catalog.
- **SC-006**: The bundled catalog ships with at least 10 well-known, actively maintained MCP servers across at least 3 categories.

## Assumptions

- The catalog is a read-only data set managed by the mcp-inator project maintainers; users cannot submit or publish catalog entries in this version (community submission is a future feature).
- Catalog data is structured and stored in a format the app can parse locally (format details are an implementation concern).
- The remote catalog refresh endpoint is controlled by the mcp-inator project and is not a third-party dependency beyond the maintainers' control.
- "One click" in the feature description means one tap/action to initiate the add flow; the user still reviews and saves the pre-populated form (they are not forced into a blind save).
- Agent config files are never modified by the catalog feature; writes are triggered only through the existing enable/disable flows in the config library.
- The catalog does not replace the manual "Add Server" flow; both remain available simultaneously.
- Catalog entries provide defaults only — users may override any pre-populated field before saving.
- Cross-machine sync of the user's catalog refresh timestamp is out of scope; the timestamp is local to each device.

## Clarifications

### Session 2026-05-25

- Q: Should the catalog support offline-first with optional remote refresh, or require internet? → A: Offline-first with bundled data always available; remote refresh is optional and non-blocking.
- Q: Can users submit new servers to the catalog from within the app? → A: No — catalog is maintainer-curated in this version; community submission is a future feature.
- Q: Does "one click / one tap" mean blind save or open a pre-filled form? → A: Opens the pre-filled Add/Edit Config form for review; user explicitly saves.
