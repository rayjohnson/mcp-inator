# Quickstart: Publishing a Release

## One-Time Setup (do once, not per release)

### 1. Generate Ed25519 keys

```bash
# Find Sparkle's generate_keys tool after opening the project in Xcode
# (SPM downloads it automatically)
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" 2>/dev/null | head -1

# Run it — saves private key to your login Keychain automatically
./path/to/generate_keys
# Output:
# Public key (put this in Info.plist as SUPublicEDKey):
# pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=
```

### 2. Add public key to project.yml

```yaml
# In project.yml, under targets.mcp-inator.info.properties:
SUPublicEDKey: "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="
```

Then regenerate the Xcode project: `xcodegen generate`

### 3. Export private key and store as GitHub secret

```bash
# Export private key from Keychain (Security → Sparkle account)
# or re-run generate_keys with --account flag to display it
# Store the exported base64 string as GitHub Actions secret: SPARKLE_PRIVATE_KEY
```

### 4. Enable GitHub Pages

In the GitHub repo: **Settings → Pages → Source: Deploy from branch → `gh-pages`**

### 5. Make repo public

In the GitHub repo: **Settings → General → Danger Zone → Change repository visibility → Public**

### 6. Create initial gh-pages branch and appcast

```bash
git checkout --orphan gh-pages
git reset --hard
# Create placeholder appcast with no items
cat > appcast.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>mcp-inator</title>
    <link>https://github.com/rayjohnson/mcp-inator</link>
    <description>mcp-inator releases</description>
  </channel>
</rss>
EOF
git add appcast.xml && git commit -m "Initialize appcast"
git push origin gh-pages
git checkout main
```

---

## Publishing a Release

```bash
# 1. Ensure main is clean and all changes merged
git checkout main && git pull

# 2. Tag the release (semver, v prefix)
git tag v0.2.0
git push origin v0.2.0

# 3. Watch the GitHub Actions release workflow
# Go to: Actions → release.yml → latest run

# 4. Verify
# - DMG appears on: github.com/rayjohnson/mcp-inator/releases/tag/v0.2.0
# - Appcast updated: rayjohnson.github.io/mcp-inator/appcast.xml
# - Existing app shows update notification on next launch
```

---

## Gatekeeper Bypass (for end users)

Include in GitHub Release description:

```markdown
## Installation

1. Download `mcp-inator-X.Y.Z.dmg`
2. Open the DMG and drag mcp-inator to Applications
3. On first launch, macOS may block the app. To open it:
   - **Right-click** mcp-inator.app → **Open** → **Open**
   - Or run in Terminal: `xattr -dr com.apple.quarantine /Applications/mcp-inator.app`
```

---

## Verifying Sparkle Signature Locally

```bash
# Find sign_update tool
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" 2>/dev/null | head -1

# Verify signature matches what's in appcast
./path/to/sign_update mcp-inator-0.2.0.dmg
# Should output the same sparkle:edSignature as in appcast.xml
```
