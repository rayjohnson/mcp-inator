# Quickstart: In-App Help & README Overhaul

Manual test scenarios. Run after implementation to verify the feature.

## Scenario 1 — In-App Help (Menu Bar Mode)

1. Build and launch the app (menu bar mode, `showInDock = false`)
2. Click the menu bar icon to open the popover
3. Scroll to the footer — verify a **"Help…"** button appears alongside "About" and "Preferences"
4. Click **"Help…"** — verify a native window opens with the help content
5. Scroll through the help window and verify all four sections are present:
   - What is mcp-inator?
   - Adding and Configuring Servers
   - The Catalog
   - Usage Sharing
6. Disconnect from the network (or disable Wi-Fi) — close and reopen the Help window — verify it loads instantly with no spinner or error

## Scenario 2 — In-App Help (Dock Mode)

1. Enable dock mode: Preferences → General → "Show in Dock"
2. Open the Application menu → Help → **"mcp-inator Help…"**
3. Verify the same help window opens with identical content
4. Verify the popover footer Help button also still works in dock mode

## Scenario 3 — Preferences Inline Copy

1. Open Preferences → scroll to "Contributing Usage Data"
2. When not opted in: verify a brief description of what is shared appears inline (not just "You'll be prompted…")
3. When opted in (`sharingConsented = true`): verify the description is still visible alongside the Withdraw button

## Scenario 4 — README Evaluation

1. Open `README.md` in a Markdown previewer (GitHub or VS Code)
2. Verify: first two paragraphs clearly explain what the app does
3. Verify: Quick Start section has ≤ 3 steps to get the app running
4. Verify: Features section covers server management, catalog, agent support, usage sharing
5. Verify: Privacy section is present and accurate
6. Verify: "Contributing" links to `CONTRIBUTING.md`

## Scenario 5 — Contributing Guide

1. Open `CONTRIBUTING.md`
2. Follow the build instructions from scratch (or verify against a fresh clone)
3. Verify the PR checklist matches the requirements in `CLAUDE.md`
