# Data Model: GitHub Releases & Sparkle Distribution

## Entities

### Release
A versioned publication of the app. Created by pushing a `v*` git tag.

| Field | Source | Notes |
|-------|--------|-------|
| `version` (marketing) | git tag, e.g. `v0.2.0` → `0.2.0` | `CFBundleShortVersionString` |
| `buildNumber` | `GITHUB_RUN_NUMBER` | `CFBundleVersion` — must be monotonically increasing integer |
| `dmgFilename` | `mcp-inator-<version>.dmg` | Asset uploaded to GitHub Release |
| `dmgSize` | bytes, output of `sign_update` | Written to appcast `length` attribute |
| `edSignature` | base64, output of `sign_update` | Written to appcast `sparkle:edSignature` |
| `downloadURL` | GitHub Release asset URL | Written to appcast `<enclosure url>` |
| `pubDate` | CI timestamp (RFC 2822) | Written to appcast `<pubDate>` |

### Appcast (appcast.xml)
RSS 2.0 XML file with `xmlns:sparkle` namespace. Hosted at:
`https://rayjohnson.github.io/mcp-inator/appcast.xml`

Maintains the full history of releases as `<item>` entries (newest first).

### Ed25519 Key Pair
| Item | Location |
|------|----------|
| Private key | macOS Keychain (developer machine) + `SPARKLE_PRIVATE_KEY` GitHub Actions secret |
| Public key | `SUPublicEDKey` in `project.yml` Info.plist properties |

## State Transitions

```
git tag v*
    │
    ▼
GitHub Actions release.yml triggered
    │
    ├─ Build universal binary (xcodebuild archive)
    ├─ Create DMG (create-dmg)
    ├─ Sign DMG (sign_update → edSignature + length)
    ├─ Upload DMG to GitHub Release
    ├─ Generate/prepend appcast item
    └─ Push appcast.xml to gh-pages branch
         │
         ▼
    GitHub Pages serves updated appcast
         │
         ▼
    Sparkle (in running app) polls appcast
         │
         ▼
    User sees update notification → installs → app relaunches
```
