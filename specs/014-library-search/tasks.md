# Tasks: Library Search & Filter

**Input**: Design documents from `specs/014-library-search/`

**Branch**: `014-library-search`

**Single file changes**: All implementation touches only `mcp-inator/UI/ConfigLibraryView.swift`. No new files in the main target. One new test file.

---

## Phase 1: Setup

No setup required — this feature modifies one existing file with no new dependencies or infrastructure.

---

## Phase 2: Foundational

No separate foundation phase — no new models, services, or shared infrastructure. All work is scoped to `ConfigLibraryView`.

---

## Phase 3: User Story 1 — Find a Server by Name (Priority: P1) 🎯 MVP

**Goal**: User types in a search bar and the server list immediately filters to entries whose display name matches the query.

**Independent Test**: Add 10+ servers to the library. Type a partial name. Verify only matching entries appear. Clear the field — all entries return. Tab away and back — search is cleared.

### Implementation for User Story 1

- [ ] T001 [US1] Add `@State private var searchText = ""`, extract an `internal` free function `filterConfigs(_ configs: [MCPServerConfig], query: String) -> [MCPServerConfig]` (matching on `displayName` only), and add `filteredConfigs` computed property that delegates to it — all in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T002 [US1] Replace `ForEach(store.configs)` with `ForEach(filteredConfigs)` and add `.searchable(text: $searchText, prompt: "Search servers…")` modifier at the same level as `.navigationTitle` in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T003 [P] [US1] Add search-results-empty branch to `body`: when `store.configs` is non-empty but `filteredConfigs` is empty, show a "No servers match «\(searchText)»" VStack (macOS 13-compatible fallback, not `ContentUnavailableView`) in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T004 [P] [US1] Add `.onDisappear { searchText = "" }` to `ConfigLibraryView.body` to reset search when user switches tabs in `mcp-inator/UI/ConfigLibraryView.swift`

**Checkpoint**: Search bar visible in both menu bar and dock modes. Typing filters by name. Empty-search state shown correctly. Tab-switch resets field.

---

## Phase 4: User Story 2 — Find a Server by Command or Description (Priority: P2)

**Goal**: The filter also matches on command string and URL (for HTTP servers), so users can find servers by what they remember about how they run.

**Independent Test**: Add a server with display name "Payments" and command `npx stripe-mcp`. Search "stripe" — it appears. Search "npx" — all npm-based servers appear.

**Depends on**: T001 (extends the same `filteredConfigs` property)

### Implementation for User Story 2

- [ ] T005 [US2] Extend `filteredConfigs` in `ConfigLibraryView` to also match `$0.displayCommand.localizedCaseInsensitiveContains(q)` and, for HTTP servers, `$0.url.localizedCaseInsensitiveContains(q)` in `mcp-inator/UI/ConfigLibraryView.swift`

**Checkpoint**: Searching "npx" surfaces all npm-based servers. Searching a domain/URL fragment finds HTTP servers.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T006 Add unit tests covering: name match, command match, HTTP URL match, case-insensitive match, empty query returns all, no-match returns empty, tap-to-edit unaffected by active filter, swipe-to-delete reachable on filtered result — in `mcp-inatorTests/Unit/ConfigLibraryViewTests.swift` (new file)
- [ ] T007 Run `make lint` and fix any violations in `mcp-inator/UI/ConfigLibraryView.swift`
- [ ] T008 Bump `VERSION` from `0.4.8` → `0.4.9` in `VERSION`
- [ ] T009 Add entry to `RELEASE_NOTES.md`: "Search bar in Servers tab — type to filter by name or command"

---

## Dependencies & Execution Order

```
T001 → T002 → T003 (parallel with T004)
             → T004 (parallel with T003)
T001 → T005  (after US1 complete)
T001–T005 → T006 → T007 → T008 → T009
```

- **T003 and T004** are independent of each other (both depend on T002) — can be done in parallel
- **T005** extends the computed property from T001 — do after T001 at minimum, ideally after full US1 is working
- **T006–T009** are polish, run after all implementation is verified

---

## Parallel Opportunities

All US1 implementation is in one file so true parallelism is limited, but T003 and T004 touch different sections of `body` and can be written simultaneously:

```
# After T002 is complete, these two are independent:
T003: Add empty-search-state branch to body
T004: Add .onDisappear reset
```

---

## Implementation Strategy

### MVP (User Story 1 only — ~30 min)

1. T001: Add state + `filteredConfigs` (name-only)
2. T002: Wire `.searchable()` + swap `ForEach` source
3. T003: Empty-search state
4. T004: Reset on disappear
5. **Validate manually**: Confirm search works in both menu bar and dock modes

### Full Delivery

6. T005: Extend filter to command/URL
7. T006: Unit tests
8. T007–T009: Pre-PR checklist

---

## Notes

- No new model fields, no schema changes, no migrations needed
- `statusMatrix` is unaffected — it loads all configs and `ConfigRow` looks up by UUID, so filtering the list doesn't break agent-state display
- `.searchable()` renders in the NavigationStack toolbar in both menu bar mode (confirmed: wrapped in `NavigationStack` in `MenuBarView.swift`) and dock mode (`NavigationSplitView`)
- Drag-to-reorder is not currently implemented in `ConfigLibraryView` — no need to disable it during search
