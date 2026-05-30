# Contract: servers.json

**File**: `rayjohnson/mcp-catalog/servers.json`  
**Updated by**: Human curator (PR merge only — no automated writes)  
**Consumed by**: mcp-inator app (raw GitHub URL fetch)

---

## Schema

```json
{
  "metadata": {
    "schemaVersion": "2",
    "bundledAt": "<ISO 8601 timestamp>",
    "entryCount": 42
  },
  "entries": [
    {
      "id": "github",
      "displayName": "GitHub",
      "category": "Code & Development",
      "shortDescription": "Interact with GitHub repositories, issues, pull requests, and workflows.",
      "curatorNote": "The official first-party GitHub MCP server. Covers most common GitHub operations. Requires a PAT with repo scope.",
      "transportType": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "url": "",
      "envVars": [
        {
          "name": "GITHUB_PERSONAL_ACCESS_TOKEN",
          "description": "GitHub personal access token with repo scope. Create at github.com/settings/tokens.",
          "isRequired": true,
          "isSensitive": true
        }
      ],
      "requiredArgs": [],
      "documentationURL": "https://github.com/modelcontextprotocol/servers/tree/main/src/github",
      "repositoryURL": "https://github.com/modelcontextprotocol/servers",
      "isVerified": true,
      "isFirstParty": true,
      "alternativeTo": null,
      "serverKey": "github"
    }
  ]
}
```

---

## Field Rules

| Field | Constraint |
|-------|-----------|
| `id` | Globally unique. Snake-case or hyphen-case. Never reused after deletion. |
| `serverKey` | Must equal `id` unless there's a legacy mismatch. |
| `category` | Must be one of the seven supported categories (see data-model.md). |
| `shortDescription` | Max 120 characters. No trailing period required. No marketing language. |
| `curatorNote` | Optional. 1–3 sentences. Plain English. May include gotchas. |
| `transportType` | `"stdio"` or `"http"`. |
| `command` | Non-empty string. Known package manager or explicit path. |
| `args` | Array, may be empty. |
| `url` | Empty string `""` for stdio; URL string for http transport. |
| `envVars` | Array, may be empty. Order: required first, then optional. |
| `isFirstParty` | `true` only when the maintainer org is the company that owns the service. |
| `alternativeTo` | If set, must reference the `id` of another entry in the same file. |

## schemaVersion

- `"1"` — original bundled catalog format (no `curatorNote`, `isFirstParty`, `alternativeTo`, `requiredArgs`)  
- `"2"` — extended format with new fields; all new fields are optional so v1 consumers degrade gracefully

## Backward Compatibility

The app's JSON decoder must use `decodeIfPresent` for all new fields. A missing `curatorNote` renders as no note shown. A missing `isFirstParty` defaults to `false`. A missing `alternativeTo` means this entry is not a ranked alternative.
