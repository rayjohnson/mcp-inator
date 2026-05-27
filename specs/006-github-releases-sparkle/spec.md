# Feature Specification: GitHub Releases & Sparkle Auto-Update Distribution

**Feature Branch**: `006-github-releases-sparkle`

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: "Distribution via GitHub Releases with Sparkle auto-update."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Developer publishes a new release (Priority: P1)

A developer tags a release in the repository. An automated pipeline builds the app, packages it into a DMG, signs it with Sparkle's Ed25519 key, uploads it to GitHub Releases, and updates the public appcast so existing users receive the update automatically.

**Why this priority**: This is the core capability. Without a repeatable, automated release process there is no distribution.

**Independent Test**: Tag a release on the repository; confirm a DMG appears on GitHub Releases and the appcast reflects the new version — all without any manual steps beyond the tag.

**Acceptance Scenarios**:

1. **Given** a developer pushes a git tag matching `v*`, **When** the CI pipeline runs, **Then** a signed DMG is uploaded to GitHub Releases and the appcast is updated within 10 minutes.
2. **Given** the pipeline has run, **When** a user opens the appcast URL in a browser, **Then** it contains a valid entry for the new version with a correct download URL and Ed25519 signature.
3. **Given** the pipeline fails at any step, **When** the developer checks CI, **Then** the failure is clearly reported and no partial/corrupt release is published.

---

### User Story 2 - Existing user receives an in-app update (Priority: P1)

A user already running mcp-inator sees a notification that a new version is available. They click "Install Update", the app downloads and verifies the update, and relaunches into the new version — without visiting any website or manually downloading anything.

**Why this priority**: Auto-update is the primary user-facing value of this feature. Without it, users stay on stale versions indefinitely.

**Independent Test**: Run an older build against a live appcast that advertises a newer version; confirm the update dialog appears, the download completes, and the app relaunches at the new version.

**Acceptance Scenarios**:

1. **Given** a newer version is listed in the appcast, **When** the app launches or reaches its check interval, **Then** an update notification is shown to the user.
2. **Given** the update notification is shown, **When** the user clicks "Install and Relaunch", **Then** the app downloads, verifies the Ed25519 signature, installs, and relaunches at the new version.
3. **Given** the user dismisses the update notification, **When** the app relaunches later, **Then** the update check runs again at the next interval.
4. **Given** the downloaded update has an invalid or missing signature, **When** Sparkle attempts to install it, **Then** the update is rejected and an error is shown to the user.

---

### User Story 3 - New user downloads and runs the app for the first time (Priority: P2)

A developer hears about mcp-inator and downloads the DMG from the GitHub Releases page. They open the DMG, drag the app to Applications, and launch it. They are told clearly how to bypass the macOS Gatekeeper warning (since the app is not notarized) and the app runs successfully.

**Why this priority**: First-run experience is important but requires no code change to the app itself — primarily documentation and a clear download page.

**Independent Test**: Download the DMG from GitHub Releases on a clean Mac, attempt to open it, follow the documented bypass steps, and confirm the app launches.

**Acceptance Scenarios**:

1. **Given** a user downloads the DMG and drags the app to Applications, **When** they double-click to launch, **Then** macOS shows the Gatekeeper warning.
2. **Given** the Gatekeeper warning appears, **When** the user follows the documented bypass (right-click → Open, or the `xattr` command), **Then** the app launches successfully.
3. **Given** the GitHub Releases page, **When** a user visits it, **Then** they can find the latest DMG download and a link to the Gatekeeper bypass instructions.

---

### User Story 4 - Homebrew Cask install (Priority: P3 — Phase 2 stub)

A developer installs mcp-inator via `brew install --cask mcp-inator` without needing to visit GitHub or handle the Gatekeeper warning manually.

**Why this priority**: Phase 2 only. Homebrew provides discoverability and removes first-run friction for developers, but requires the app to be stable and publicly released first.

**Independent Test**: Run `brew install --cask mcp-inator` on a clean Mac and confirm the app is installed and launchable.

**Acceptance Scenarios**:

1. **Given** mcp-inator is in a Homebrew tap, **When** a user runs `brew install --cask mcp-inator`, **Then** the app is downloaded, Gatekeeper quarantine is cleared, and the app is available in /Applications.

---

### Edge Cases

- What happens if the appcast is unreachable (user is offline or the host is down)? The app must fail silently without crashing or blocking launch.
- What happens if a release is published with a corrupt or missing DMG? The pipeline must detect and report the failure before updating the appcast.
- What happens if the user's Mac architecture differs from the build (Intel vs Apple Silicon)? The DMG must be a universal binary or the appcast must advertise architecture-specific builds.
- What happens if the repository visibility change breaks existing GitHub Actions workflows or secrets?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST be made public with no open-source license (all rights reserved under copyright).
- **FR-002**: Pushing a git tag matching `v*` MUST trigger an automated pipeline that builds, packages, and publishes a release without manual intervention.
- **FR-003**: The automated pipeline MUST produce a DMG containing the app.
- **FR-004**: The DMG MUST be signed with a Sparkle Ed25519 private key before publication.
- **FR-005**: The signed DMG MUST be uploaded as an asset on the corresponding GitHub Release.
- **FR-006**: The pipeline MUST update a public `appcast.xml` file hosted on GitHub Pages after each successful release.
- **FR-007**: The `appcast.xml` MUST include the version number, release date, download URL, file size, and Ed25519 signature for each release.
- **FR-008**: The app MUST integrate the Sparkle framework and check the appcast for updates on launch and periodically thereafter.
- **FR-009**: When an update is available, the app MUST present a native update dialog showing the version and release notes.
- **FR-010**: The app MUST verify the Ed25519 signature of any downloaded update before installing it.
- **FR-011**: Update checks MUST fail silently if the appcast is unreachable, without affecting app startup or usability.
- **FR-012**: The GitHub Pages site MUST serve the appcast at a stable public URL that does not change between releases.
- **FR-013**: The app MUST be built as a universal binary (Apple Silicon + Intel) or the appcast MUST serve architecture-specific builds.
- **FR-014**: The GitHub Releases page MUST include download instructions and a link to the Gatekeeper bypass documentation.
- **FR-015**: The Sparkle Ed25519 private key MUST be stored as a GitHub Actions secret and never committed to the repository.

### Key Entities

- **Release**: A versioned, packaged build of the app published to GitHub Releases, identified by a semver tag.
- **DMG**: A macOS disk image containing the app bundle, signed with the Sparkle Ed25519 key for update integrity.
- **Appcast**: An XML file (RSS-based) hosted publicly on GitHub Pages that describes available releases for Sparkle to consume.
- **Ed25519 Key Pair**: A signing key pair used by Sparkle to verify update authenticity. Private key stored in CI secrets; public key embedded in the app.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new release is published end-to-end (tag → DMG on GitHub Releases + updated appcast) in under 10 minutes with no manual steps.
- **SC-002**: 100% of published updates are rejected by Sparkle if the Ed25519 signature does not match.
- **SC-003**: An existing user on the previous version sees the update notification within one app launch of a new release being published.
- **SC-004**: A new user can download, bypass Gatekeeper, and launch the app in under 5 minutes following the documented instructions.
- **SC-005**: The app launches and operates normally when the appcast host is unreachable (update check fails silently).

## Assumptions

- The app is not submitted to the Mac App Store; distribution is exclusively via GitHub Releases (and eventually Homebrew Cask).
- No Apple Developer account is required; notarization is out of scope. The target audience (developers) is comfortable with the one-time Gatekeeper bypass.
- The app is built as a universal binary (Apple Silicon + Intel) using a single DMG. Architecture-specific builds are not needed.
- The `appcast.xml` is hosted on the `gh-pages` branch of the same repository using GitHub Pages (free, no custom domain required).
- Release notes are written manually by the developer as part of the GitHub Release; Sparkle displays the GitHub Release description.
- Sparkle is added as a Swift Package dependency.
- The Sparkle Ed25519 key pair is generated once, stored securely, and rotated only if compromised.
- Homebrew Cask (Phase 2) is not implemented in this feature; only a stub user story is included to preserve planning context.
- The repository has no existing GitHub Actions CI workflows that conflict with the release pipeline.
