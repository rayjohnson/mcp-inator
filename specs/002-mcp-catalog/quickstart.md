# Quickstart: MCP Server Catalog

How to build and test the catalog feature end-to-end.

## Adding a new entry to the catalog

1. Edit `catalog/catalog.json` at the repo root.
2. Add a new object to the `entries` array following the schema in `contracts/catalog-json-schema.md`.
3. Increment `metadata.entryCount`.
4. Copy the updated file to `mcp-inator/Resources/catalog.json` (the bundle copy).
5. Build and run — the new entry appears immediately in the Catalog tab.

## Testing the remote refresh

The app fetches from:
```
https://raw.githubusercontent.com/rayjohnson/mcp-inator/main/catalog/catalog.json
```

To test locally without a deploy:
1. Edit `CatalogStore.swift` and temporarily replace the remote URL with a `localhost` URL.
2. Serve the file locally: `python3 -m http.server 8080` from the repo root.
3. Tap the refresh button in the Catalog tab.
4. Verify the App Support copy is updated: `cat ~/Library/Application\ Support/mcp-inator/catalog.json`.

## Verifying "Already in library"

1. Add any catalog entry to your library via the Catalog tab.
2. Navigate back to the Catalog tab and find the same entry.
3. It should show an "In Library" badge and the button should read "Edit in Library".

## Running catalog unit tests

```bash
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug test \
  -only-testing mcp-inatorTests/CatalogStoreTests
```

## Key files

| File | Purpose |
|---|---|
| `catalog/catalog.json` | Remote source — update this to add/edit entries |
| `mcp-inator/Resources/catalog.json` | Bundle copy — keep in sync with above |
| `mcp-inator/Models/CatalogEntry.swift` | Data model |
| `mcp-inator/Services/CatalogStore.swift` | Load/refresh/filter logic |
| `mcp-inator/UI/CatalogView.swift` | Catalog tab UI |
| `mcp-inator/UI/CatalogDetailView.swift` | Entry detail sheet |
