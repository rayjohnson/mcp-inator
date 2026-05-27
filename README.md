# mcp-inator

A macOS menu bar app for managing MCP server configurations across AI agents (Claude Code, Claude Desktop, Gemini CLI, Codex CLI, and more).

## Installation

### One-line install

```bash
curl -fsSL https://rayjohnson.github.io/mcp-inator/install.sh | bash
```

This downloads the latest release, installs it to `/Applications`, and clears the Gatekeeper quarantine flag automatically.

### Manual install

1. Download the latest `mcp-inator-X.Y.Z.dmg` from [GitHub Releases](https://github.com/rayjohnson/mcp-inator/releases)
2. Open the DMG and drag **mcp-inator** to your Applications folder
3. On first launch, macOS will block the app — right-click → **Open** to bypass, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/mcp-inator.app
   ```

### Uninstall

```bash
curl -fsSL https://rayjohnson.github.io/mcp-inator/uninstall.sh | bash
```

Removes the app and its data. Your agent configurations (Claude, Gemini, etc.) are not touched.

### Updates

Once installed, mcp-inator updates itself automatically via the built-in updater.

## Requirements

- macOS 13.0 or later

## Building from Source

```bash
xcodegen generate
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug build
```

## License

Copyright © 2026 Ray Johnson. All rights reserved.
