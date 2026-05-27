# mcp-inator

A macOS menu bar app for managing MCP server configurations across AI agents (Claude Code, Claude Desktop, Gemini CLI, Codex CLI, and more).

## Installation

1. Download the latest `mcp-inator-X.Y.Z.dmg` from [GitHub Releases](https://github.com/rayjohnson/mcp-inator/releases)
2. Open the DMG and drag **mcp-inator** to your Applications folder

### First Launch (Gatekeeper)

Because mcp-inator is not notarized, macOS will block the first launch. Use either method:

**Option A — Right-click open** (one-time, no Terminal needed)
1. Right-click (or Control-click) `mcp-inator.app` in Applications
2. Choose **Open**
3. Click **Open** in the dialog

**Option B — Remove quarantine flag**
```
xattr -dr com.apple.quarantine /Applications/mcp-inator.app
```

### Subsequent Updates

Future updates are delivered automatically — mcp-inator will notify you when a new version is available.

## Requirements

- macOS 13.0 or later

## Building from Source

```
xcodegen generate
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug build
```

## License

Copyright © 2026 Ray Johnson. All rights reserved.
