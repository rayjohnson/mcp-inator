# Private Catalogs

Private catalogs let teams share internal MCP servers through mcp-inator without publishing them to the public catalog. Each private catalog URL you configure appears as its own tab — visible only to people who add that URL.

## How It Works

You host a JSON file (anywhere your team can reach it — an internal URL, a private GitHub Gist, an S3 bucket, etc.). mcp-inator fetches it and displays the servers it describes in a dedicated tab. No authentication — the URL itself is the access control.

## JSON Format

```json
{
  "tabName": "Acme Internal",
  "servers": [
    {
      "id": "acme-data-pipeline",
      "displayName": "Data Pipeline",
      "category": "developer-tools",
      "shortDescription": "Acme's internal data pipeline MCP server.",
      "command": "npx",
      "args": ["-y", "@acme/data-pipeline-mcp"],
      "envVars": [
        {
          "key": "ACME_API_KEY",
          "description": "Your Acme API key",
          "isRequired": true
        }
      ]
    }
  ]
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `tabName` | Yes | Label shown on the catalog tab |
| `servers` | Yes | Array of server entries (see below) |

Each entry in `servers` uses the same format as the public catalog:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier for the server |
| `displayName` | Yes | Name shown in the UI |
| `category` | Yes | One of: `developer-tools`, `data-analysis`, `productivity`, `communication`, `infrastructure`, `ai-ml`, `other` |
| `shortDescription` | Yes | One-sentence description |
| `command` | Yes | Executable to run (e.g. `npx`, `uvx`, `node`) |
| `args` | No | Array of arguments |
| `envVars` | No | Array of environment variable definitions |

Each `envVars` entry:

| Field | Required | Description |
|-------|----------|-------------|
| `key` | Yes | Environment variable name |
| `description` | No | Shown in the UI to help the user fill it in |
| `isRequired` | No | Whether mcp-inator marks it as required (default: `false`) |

## Adding a Private Catalog URL

1. Open mcp-inator → **Preferences**
2. Scroll to **Private Catalogs**
3. Paste the URL of your catalog JSON file and click **Add**

The tab appears immediately. mcp-inator fetches the catalog at launch and whenever you add or remove a URL. If a URL is unreachable, the tab simply won't appear — no error dialog.

## Tips

- **Host it anywhere your team can reach.** A private GitHub Gist, an internal web server, an S3 bucket with a signed URL, or even a static file server all work.
- **Updates are automatic.** mcp-inator re-fetches on every launch. Edit the JSON file and your team sees the updated servers next time they start the app.
- **Multiple catalogs.** Add as many URLs as you like — each gets its own tab.
- **Offline fallback.** mcp-inator caches each catalog locally. If the URL is temporarily unreachable, the last successful fetch is used.
