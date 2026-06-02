# Data Model: In-App Help Content

The help content is static — no persistence, no network. This document defines the topic structure and copy outline for `HelpView.swift`.

**Tone**: Friendly and tutorial-style. Write as if explaining to a developer who is technically capable but has never heard of mcp-inator. Use "you" and "your". Avoid jargon where possible; introduce terms briefly when needed.

## HelpView Structure

`HelpView` is a single scrollable SwiftUI view with named sections. No tab bar needed — the content fits in one linear flow with clear section headings.

## Sections

### 1. What is mcp-inator?

**Purpose**: One-paragraph overview for users who opened Help without reading the README.

**Content outline**:
- mcp-inator manages your MCP server configurations so you don't have to set them up separately in each AI tool.
- You configure a server once; the app writes it to Claude, Gemini, Cursor, Zed, and any other supported agent automatically.
- Runs as a menu bar app (no dock icon by default).

---

### 2. Adding and Configuring Servers

**Purpose**: Step-by-step for the most common user action.

**Content outline**:
- Click the menu bar icon to open the server list.
- Tap **+** to add a server: enter a name, command, arguments, and any required environment variables.
- Toggle the checkbox next to an agent name to enable or disable the server for that agent.
- Use the **Private server** toggle to exclude a server from usage reports.

---

### 3. The Catalog

**Purpose**: Explain the catalog and how to use it to install servers.

**Content outline**:
- The Catalog tab shows a curated list of popular MCP servers with pre-filled defaults.
- Tap any entry to see its description, required environment variables, and usage stats.
- Tap **Add to Library** to add it to your server list with one tap — no manual entry required.
- The catalog is fetched from GitHub and cached locally; it works offline after the first load.

---

### 4. Usage Sharing

**Purpose**: Transparent explanation of what the opt-in telemetry sends (and doesn't send).

**Content outline**:
- mcp-inator can optionally report which MCP servers you use to help surface popular ones in the catalog.
- **What is shared**: server key names (e.g., `filesystem`, `github-mcp`), command basename, argument structure (filesystem paths are replaced with `<path>`), and environment variable key names only — never values.
- **What is never shared**: environment variable values, server command full paths, private servers (marked with the Private toggle), servers you exclude on the review screen, or any personally identifiable information.
- You're prompted to opt in after 7 days of use. You can withdraw at any time from Preferences → Contributing Usage Data.

---

## README Sections

The new `README.md` will contain:

1. **Hero**: one-sentence description + screenshot(s)
2. **Installation**: one-line install, manual install, uninstall (already exists — preserve and polish)
3. **Quick Start**: launch → add first server → apply to an agent (3 steps max)
4. **Features**: server management, catalog, agent support matrix, usage sharing opt-in
5. **Privacy**: 3–4 sentence summary matching the in-app help copy above

## Screenshots

Screenshots are a manual capture step. The plan calls for at minimum:
- Menu bar popover (server list visible) — hero shot
- Catalog view

Additional shots that may add value (decide during implementation):
- Add server form
- Preferences window
- Help window itself

**Capture workflow**: Launch the app, position the window, use `screencapture` to capture. Save to `docs/images/` with version suffix (e.g., `menubar-v0.5.0.png`) so staleness is obvious.
