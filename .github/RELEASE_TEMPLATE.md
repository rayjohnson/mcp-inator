## What's New

<!-- Summarize the changes in this release -->

---

## Installation

Download `mcp-inator-X.Y.Z.dmg` below, open it, and drag **mcp-inator** to your Applications folder.

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
Then double-click to launch normally.

### Subsequent Updates

Future updates are delivered automatically via the built-in updater — no manual download required.
