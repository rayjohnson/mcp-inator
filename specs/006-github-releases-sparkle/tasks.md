---
description: "Task list for GitHub Releases & Sparkle Distribution feature"
---

# Tasks: GitHub Releases & Sparkle Distribution

**Input**: Design documents from `/specs/006-github-releases-sparkle/`

**Branch**: `006-github-releases-sparkle`

**Organization**: Tasks are grouped by user story. Each story is independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other [P] tasks in the same phase
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (One-Time Manual Prerequisites)

**Purpose**: Establish the Ed25519 key pair, GitHub Pages infrastructure, and repo visibility. These are manual steps done once by the developer. Nothing can proceed until they are complete.

**⚠️ CRITICAL**: These are manual steps, not code changes. Complete all of them before Phase 2.

- [ ] T001 Generate the Sparkle Ed25519 key pair by finding and running `generate_keys` from the Sparkle SPM checkout under `~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/Sparkle/bin/generate_keys`; note the public key string output and confirm the private key is saved to the macOS login Keychain under account "ed25519"
- [ ] T002 Add `SUPublicEDKey: "<public-key-from-T001>"` to `project.yml` under `targets.mcp-inator.info.properties`; run `xcodegen generate`; open the built app's Info.plist in Finder and confirm `SUPublicEDKey` is present with the correct value
- [ ] T003 Export the private key from the macOS Keychain (open Keychain Access → login → find "ed25519" entry → Show Password) and save the base64 string as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY` at `github.com/rayjohnson/mcp-inator/settings/secrets/actions`
- [ ] T004 Create the `gh-pages` branch and push an initial `appcast.xml` with no `<item>` entries (see quickstart.md template); verify the branch exists on origin with `git ls-remote --heads origin gh-pages`
- [ ] T005 Enable GitHub Pages in repository Settings → Pages → Source: Deploy from branch → `gh-pages`, root `/`; wait for the first deployment and confirm `https://rayjohnson.github.io/mcp-inator/appcast.xml` returns valid XML
- [ ] T006 Change repository visibility to Public in GitHub Settings → General → Danger Zone → Change repository visibility → Public; confirm the repo is accessible without authentication

**Checkpoint**: `SUPublicEDKey` in project.yml; appcast URL returns XML; repo is public; `SPARKLE_PRIVATE_KEY` secret is set.

---

## Phase 2: Release Pipeline (User Story 1 — Automated Release) 🎯 MVP

**Goal**: A git tag push triggers the full pipeline: build → DMG → sign → GitHub Release → updated appcast.

**Independent Test**: Push tag `v0.1.1-test`; within 10 minutes a signed DMG appears on GitHub Releases and `appcast.xml` on GitHub Pages contains a new `<item>` with the correct `sparkle:edSignature`.

### Implementation

- [ ] T007 [US1] Create `.github/ExportOptions.plist` with `method: mac-application` and `signingStyle: manual` (no Developer ID required); commit to main branch

- [ ] T008 [US1] Create `.github/workflows/release.yml` with the following complete pipeline (trigger: `push: tags: ['v*']`, runner: `macos-15`):
  1. `actions/checkout@v4`
  2. `sudo xcode-select -s /Applications/Xcode_16.3.app`
  3. `brew install xcodegen create-dmg`
  4. `xcodegen generate`
  5. Extract version from tag: `VERSION=${GITHUB_REF_NAME#v}`
  6. `xcodebuild archive -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Release -archivePath build/mcp-inator.xcarchive MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`
  7. `xcodebuild -exportArchive -archivePath build/mcp-inator.xcarchive -exportPath build/export -exportOptionsPlist .github/ExportOptions.plist`
  8. `create-dmg --volname "mcp-inator" --icon "mcp-inator.app" 200 190 --app-drop-link 600 185 "mcp-inator-${VERSION}.dmg" "build/export/"`
  9. Write `SPARKLE_PRIVATE_KEY` secret to temp file; run `./bin/sign_update --ed-key-file sparkle_ed_key mcp-inator-${VERSION}.dmg`; capture `edSignature` and `length` from output
  10. `gh release create $GITHUB_REF_NAME --title "mcp-inator $VERSION" --generate-notes "mcp-inator-${VERSION}.dmg"`
  11. Construct the download URL: `https://github.com/rayjohnson/mcp-inator/releases/download/${GITHUB_REF_NAME}/mcp-inator-${VERSION}.dmg`
  12. Generate a new `<item>` XML block for `appcast.xml` using captured `edSignature`, `length`, download URL, `VERSION`, `GITHUB_RUN_NUMBER`, and current RFC-2822 timestamp
  13. Clone `gh-pages` branch; prepend the new `<item>` inside the `<channel>` block of `appcast.xml`; commit and push using `GITHUB_TOKEN`

- [ ] T009 [US1] Find the `sign_update` binary in the Sparkle SPM checkout and confirm the release workflow can locate it — add a step early in the workflow that finds and exports the path: `SIGN_UPDATE=$(find ~/Library/Developer/Xcode -name "sign_update" 2>/dev/null | head -1)`; update T008's sign step to use this path

- [ ] T010 [US1] Push a test tag to validate the complete pipeline end-to-end: `git tag v0.1.1-test && git push origin v0.1.1-test`; verify: (a) workflow completes green, (b) DMG appears on GitHub Releases, (c) appcast.xml at `https://rayjohnson.github.io/mcp-inator/appcast.xml` contains the new `<item>` with correct signature, (d) delete the test tag and release afterward: `git push origin --delete v0.1.1-test && gh release delete v0.1.1-test --yes`

**Checkpoint**: Full pipeline completes in under 10 minutes; DMG on GitHub Releases; appcast updated with correct Sparkle signature.

---

## Phase 3: In-App Update Validation (User Story 2 — Existing User Receives Update)

**Goal**: Confirm that a running older build detects the update published by US1 and can install it.

**Independent Test**: Run the previously built app (before the test release from T010) — it should show a Sparkle update dialog pointing to the test DMG. After T010 cleanup, test again with a real `v0.1.0` tag.

### Implementation

- [ ] T011 [US2] Build a "before" version of the app locally (or use an existing build), launch it, and wait up to 24 hours for the automatic update check — OR trigger an immediate check by calling `updaterController.updater.checkForUpdates()` via a debug menu item; confirm the Sparkle update dialog appears showing the new version from the appcast

- [ ] T012 [US2] Click "Install and Relaunch" in the Sparkle dialog; confirm the app downloads, verifies the signature (no error), installs, and relaunches at the new version; confirm `CFBundleShortVersionString` in the running app matches the released version

**Checkpoint**: Sparkle auto-update flow works end-to-end: detect → download → verify → relaunch.

---

## Phase 4: First-Run Documentation (User Story 3 — New User Downloads & Runs)

**Goal**: A new user can find, download, and launch the app using documented instructions.

**Independent Test**: On a Mac that has never run mcp-inator, download the DMG from GitHub Releases, follow the written instructions, and confirm the app launches within 5 minutes.

### Implementation

- [ ] T013 [P] [US3] Create `.github/RELEASE_TEMPLATE.md` with the standard release body: a brief "What's New" placeholder, the full Gatekeeper bypass instructions (right-click → Open method AND `xattr -dr com.apple.quarantine` method), and a note that future updates are automatic via Sparkle; this file serves as the starting point for every GitHub Release description

- [ ] T014 [P] [US3] Add an "Installation" section to `README.md` covering: (a) download link pointing to GitHub Releases, (b) drag-to-Applications instruction, (c) Gatekeeper bypass steps (matching RELEASE_TEMPLATE.md), (d) note that subsequent updates are delivered automatically in-app

- [ ] T015 [US3] Tag and publish the first real public release: `git tag v0.1.0 && git push origin v0.1.0`; edit the generated GitHub Release description to incorporate content from `RELEASE_TEMPLATE.md`; confirm the complete pipeline runs successfully and the release is publicly accessible at `github.com/rayjohnson/mcp-inator/releases`

**Checkpoint**: Public release live; README has installation instructions; a fresh install works per the documented steps.

---

## Dependencies & Execution Order

```
T001 → T002 (key gen before project.yml update)
T002 → T003 (project.yml update before storing secret — ensures public key is final)
T001, T002, T003, T004, T005, T006 must ALL complete before Phase 2

T007 → T008 (ExportOptions before release workflow references it)
T008 → T009 (workflow written before sign_update path is validated)
T009 → T010 (path confirmed before end-to-end test)

T010 (US1 complete) → T011, T012 (in-app update validation needs a published version)
T010 (US1 complete) → T013, T014 (docs can be parallel with each other)
T013, T014, T011, T012 → T015 (first real release needs docs + validation done)
```

### Parallel Opportunities

- T004, T005 can run in parallel with T001/T002/T003 (GitHub Pages setup is independent of key gen)
- T006 (make repo public) can happen any time after T004/T005
- T013 and T014 can run in parallel (different files)
- T011 and T013/T014 can run in parallel (manual testing vs docs writing)

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Complete Phase 1: all manual setup steps
2. Complete Phase 2: release workflow + end-to-end validation
3. **STOP and VALIDATE**: confirm DMG on GitHub Releases + appcast updated
4. Sparkle auto-update is now functional for any user who already has the app

### Full Delivery

1. Phase 1 + Phase 2 → automated release pipeline working
2. Phase 3 → validate in-app update flow
3. Phase 4 → first-run docs + publish v0.1.0 publicly

---

## Notes

- T001 requires Xcode to have resolved the Sparkle SPM dependency at least once (open the project in Xcode or run `xcodebuild -resolvePackageDependencies` first)
- The `sign_update` binary path in DerivedData will change after a `xcodebuild clean`; the release workflow must locate it dynamically (T009)
- `gh-pages` branch must never have the main branch's source code — it is an orphan branch containing only `appcast.xml` (and optionally a static landing page)
- `GITHUB_RUN_NUMBER` guarantees monotonically increasing `CFBundleVersion` across all builds, even if tags are created out of order
- Phase 2 stub (Homebrew Cask, US4) is intentionally not tasked — no implementation in this feature
