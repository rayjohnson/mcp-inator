# Quickstart: MCP Server Catalog

How to build and test the catalog feature end-to-end.

## Adding a new entry to the catalog

1. Edit `catalog/catalog.json` at the repo root.
2. Add a new object to the `entries` array following the schema in `contracts/catalog-json-schema.md`.
3. Increment `metadata.entryCount`.
4. Run `make sync-catalog` to copy the file to `mcp-inator/Resources/catalog.json`.
5. Build and run — the new entry appears immediately in the Catalog tab.

**Tip**: `make build` automatically runs `sync-catalog` first, so steps 4–5 collapse to just `make run`.

## Using the Catalog tab

1. Open mcp-inator from the menu bar and select the **Catalog** tab.
2. Browse or use the search bar to find an entry by name or description.
3. Tap a category chip to filter by category; tap it again (or tap **All**) to clear.
4. Tap any row to open its detail view — transport info, env vars, and documentation links are shown.
5. Tap **Add to Library** to open a pre-filled configuration form.
   - Env var values are editable inline; sensitive fields show a masked input with a reveal toggle.
   - For servers that require a path argument (Filesystem, Git, SQLite), add the path in the **Arguments** section.
6. Fill in any required values, then tap **Save**.
7. The propagation screen lets you choose which agents to enable the server for.

## Verifying "Already in Library"

1. Add any catalog entry to your library via the Catalog tab.
2. Navigate back to the same entry.
3. The detail view shows a green **In Library** badge in the header and the button reads **Edit in Library**.
4. The catalog list row shows a green checkmark on the right.

## Running catalog unit tests

```bash
make test
```

Or to run only catalog tests:

```bash
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug test \
  -only-testing:mcp-inatorTests/CatalogStoreTests \
  -only-testing:mcp-inatorTests/CatalogEntryTests
```

## Key files

| File | Purpose |
|---|---|
| `catalog/catalog.json` | Source of truth — edit this to add/update entries |
| `mcp-inator/Resources/catalog.json` | Bundle copy — keep in sync via `make sync-catalog` |
| `mcp-inator/Models/CatalogEntry.swift` | Data model (CatalogEntry, CatalogCategory, etc.) |
| `mcp-inator/Services/CatalogStore.swift` | load() and filtered(search:category:) |
| `mcp-inator/UI/CatalogView.swift` | Catalog tab: list, search bar, category chips |
| `mcp-inator/UI/CatalogDetailView.swift` | Entry detail view with Add/Edit to Library action |

## Implementation notes (divergence from plan)

- **Remote refresh deferred**: US3 (FR-009/010/011) is out of scope for v1. `CatalogStore` has no `refresh()` method; the bundle JSON is the only source. This can be added later without architectural changes.
- **Navigation approach**: The catalog detail view uses `NavigationLink` inside the tab's `NavigationStack` (same pattern as Servers/Agents tabs) rather than a sheet, to avoid macOS `MenuBarExtra` sheet re-presentation bugs.
- **Env var inline editing**: `EnvVarRow` uses `TextField`/`SecureField` for inline value editing, so catalog-prefilled empty env vars can be filled in directly without delete-and-re-add.
- **`catalog.json` path arguments**: Entries that require a filesystem path (Filesystem, Git, SQLite) ship without placeholder paths in `args`. The description explains what to add after installing.
