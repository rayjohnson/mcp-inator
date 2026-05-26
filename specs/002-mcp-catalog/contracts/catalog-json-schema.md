# Contract: catalog.json Schema

This file defines the schema for `catalog.json` — the catalog data file shipped in the app bundle and fetched from the remote refresh endpoint.

**Both copies (bundled and remote) must conform to this schema.**

---

## Top-level structure

```json
{
  "metadata": { ... },
  "entries": [ ... ]
}
```

---

## metadata object

```json
{
  "schemaVersion": "1",
  "bundledAt": "2026-05-25T00:00:00Z",
  "lastRefreshedAt": null,
  "entryCount": 12
}
```

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | string | Must be `"1"` for this version |
| `bundledAt` | ISO-8601 string | When this file was generated |
| `lastRefreshedAt` | ISO-8601 string \| null | `null` in the bundle copy |
| `entryCount` | integer | Must equal `entries.length` |

---

## entries array — one entry object

```json
{
  "id": "io.github.modelcontextprotocol/server-github",
  "displayName": "GitHub MCP",
  "category": "Code & Development",
  "shortDescription": "Interact with GitHub repositories, issues, pull requests, and code search from any MCP-compatible agent.",
  "transportType": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "url": "",
  "envVars": [
    {
      "name": "GITHUB_TOKEN",
      "description": "A GitHub personal access token with repo scope.",
      "isRequired": true,
      "isSensitive": true,
      "defaultValue": null
    }
  ],
  "documentationURL": "https://github.com/modelcontextprotocol/servers/tree/main/src/github",
  "repositoryURL": "https://github.com/modelcontextprotocol/servers",
  "isVerified": true,
  "serverKey": "github-mcp"
}
```

| Field | Type | Required | Constraints |
|---|---|---|---|
| `id` | string | ✓ | Unique within file; preferably registry reverse-DNS name |
| `displayName` | string | ✓ | Non-empty; ≤ 60 chars |
| `category` | string | ✓ | One of the 7 defined category raw values |
| `shortDescription` | string | ✓ | Non-empty; ≤ 200 chars |
| `transportType` | string | ✓ | `"stdio"`, `"http"`, or `"sse"` |
| `command` | string | stdio only | Non-empty when `transportType == "stdio"` |
| `args` | string[] | ✓ | May be empty array `[]` |
| `url` | string | http/sse only | Non-empty when `transportType == "http"` or `"sse"`; empty string otherwise |
| `envVars` | object[] | ✓ | May be empty array `[]` |
| `documentationURL` | string \| null | ✗ | Valid URL or null |
| `repositoryURL` | string \| null | ✗ | Valid URL or null |
| `isVerified` | boolean | ✓ | `true` for maintainer-curated entries |
| `serverKey` | string | ✓ | Lowercase kebab-case; must match `MCPServerConfig.generateKey(from: displayName)` |

---

## envVars entry object

```json
{
  "name": "GITHUB_TOKEN",
  "description": "A GitHub personal access token with repo scope.",
  "isRequired": true,
  "isSensitive": true,
  "defaultValue": null
}
```

| Field | Type | Required |
|---|---|---|
| `name` | string | ✓ |
| `description` | string | ✓ |
| `isRequired` | boolean | ✓ |
| `isSensitive` | boolean | ✓ |
| `defaultValue` | string \| null | ✗ |

---

## Schema versioning

`schemaVersion` is a string integer. A breaking change (renamed/removed fields) increments to `"2"`. The app checks `schemaVersion` on load; an unrecognised version falls back to the bundle copy rather than crashing.

---

## Valid category values

```
"Code & Development"
"Productivity"
"Data & Analytics"
"Communication"
"Infrastructure"
"AI & LLMs"
"Web & Browser"
```
