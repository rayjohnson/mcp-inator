# Research: GitHub Releases & Sparkle Distribution

## Findings

### Decision: Sparkle integration
- **Decision**: Sparkle 2.x via Swift Package Manager — `https://github.com/sparkle-project/Sparkle`, `from: "2.0.0"`
- **Rationale**: Already added to `project.yml` and `SPUStandardUpdaterController` is already wired in `mcp_inatorApp.swift`. `SUFeedURL` and `SUEnableAutomaticChecks` are already in Info.plist. Only missing piece is `SUPublicEDKey`.
- **Alternatives considered**: None — Sparkle is already present and partially configured.

### Decision: Ed25519 key pair
- **Decision**: Generate with Sparkle's bundled `generate_keys` tool. Public key goes in Info.plist as `SUPublicEDKey`. Private key exported from Keychain and stored as `SPARKLE_PRIVATE_KEY` GitHub Actions secret.
- **Rationale**: Sparkle's own signing is independent of Apple notarization. Provides download integrity without requiring a Developer ID.
- **Key location at generation time**: `~/.xcode/DerivedData/.../SourcePackages/checkouts/Sparkle/bin/generate_keys` or from a downloaded Sparkle release archive.
- **CI signing**: `./bin/sign_update --ed-key-file sparkle_ed25519.key <dmg>` — outputs `sparkle:edSignature` and `length` values for appcast.

### Decision: DMG creation
- **Decision**: `create-dmg` (Homebrew) on `macos-15` GitHub Actions runner (consistent with existing CI).
- **Rationale**: Higher-level than `hdiutil`, produces a properly formatted installer DMG with drag-to-Applications layout. No notarization step required.
- **Alternatives considered**: `hdiutil` (lower-level, fiddly layout); Xcode Archive/Export (requires Developer ID, out of scope).

### Decision: Appcast hosting
- **Decision**: `gh-pages` branch of the same repo, served via GitHub Pages at `https://rayjohnson.github.io/mcp-inator/appcast.xml`. URL already hardcoded in `SUFeedURL` in Info.plist.
- **Rationale**: Free, stable URL, no external hosting dependency. `peaceiris/actions-gh-pages@v4` action handles the push from the release workflow using `GITHUB_TOKEN`.
- **Alternatives considered**: `docs/` folder on `main` (simpler but commits to main from release workflow); S3/Cloudflare R2 (external cost and dependency).

### Decision: Version injection
- **Decision**: `CFBundleShortVersionString` (marketing version, e.g., `0.2.0`) is injected from the git tag during build via `-xcconfig` or xcodebuild `MARKETING_VERSION` build setting. `CFBundleVersion` (build number) uses `GITHUB_RUN_NUMBER` — a monotonically increasing integer provided by GitHub Actions.
- **Rationale**: Avoids modifying source files in CI. `CFBundleVersion` must be a strictly incrementing integer; `GITHUB_RUN_NUMBER` guarantees this automatically.

### Decision: Release trigger
- **Decision**: GitHub Actions workflow triggered on `push: tags: ['v*']`. Tag format: `v0.2.0`.
- **Rationale**: Standard convention. Decouples release publishing from PR merges. Developer tags locally and pushes; CI does the rest.

### Decision: Notarization
- **Decision**: Skipped. No Apple Developer account required.
- **Rationale**: Target audience (developers) is comfortable with right-click → Open or `xattr -dr com.apple.quarantine`. Constitution violation documented and justified. Can be added later when/if Apple Developer account is obtained.

### Decision: Repo visibility
- **Decision**: Make public with no license (all rights reserved). Copyright notice added to README.
- **Rationale**: Required for Homebrew Cask (Phase 2) and for free GitHub Pages. No open-source license means code is viewable but legally non-reusable without permission.

### Pre-existing work (no implementation needed)
- Sparkle SPM dependency: ✅ already in `project.yml`
- `SPUStandardUpdaterController`: ✅ already in `mcp_inatorApp.swift`
- `SUFeedURL`: ✅ already in `project.yml` Info.plist properties
- `SUEnableAutomaticChecks`: ✅ already in `project.yml` Info.plist properties
- `ENABLE_HARDENED_RUNTIME: YES`: ✅ already set (required for Sparkle 2.x)
