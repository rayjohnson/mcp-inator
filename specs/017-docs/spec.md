# Feature Specification: In-App Help & README Overhaul

**Feature Branch**: `feature/017-docs`

**Created**: 2026-06-02

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — New User Reads README to Evaluate the App (Priority: P1)

A developer discovers mcp-inator on GitHub and wants to understand what it does, whether it's useful to them, and how to get started. The current README doesn't answer these questions adequately.

**Why this priority**: First impression for all new users. A clear README lowers the barrier to install and drives adoption.

**Independent Test**: A person unfamiliar with mcp-inator can read the new README and answer: "What does this app do?", "How do I install it?", "What can I configure?" — without visiting any other resource.

**Acceptance Scenarios**:

1. **Given** a developer lands on the GitHub repo page, **When** they read the README, **Then** they understand what mcp-inator does in the first two paragraphs.
2. **Given** a new user wants to install the app, **When** they follow the README Quick Start section, **Then** they can install and launch the app successfully.
3. **Given** a user wants to understand how to contribute, **When** they read the contributing section, **Then** they know how to set up a dev environment and open a PR.

---

### User Story 2 — Existing User Opens In-App Help to Understand a Feature (Priority: P2)

A user inside the running app has a question — "How do I add a new MCP server?", "What does the catalog do?", "What data does usage sharing send?" — and wants answers without leaving the app.

**Why this priority**: Reduces friction and support burden for users already engaged with the app.

**Independent Test**: With the app running and no internet required, a user can open the Help content and find answers to the three most common questions about the app's features.

**Acceptance Scenarios**:

1. **Given** the app is running, **When** a user clicks the Help button/menu item, **Then** a help view opens inside the app.
2. **Given** the help view is open, **When** the user reads it, **Then** they find explanations for: what mcp-inator does, how to add/configure servers, what the catalog is, and what usage sharing sends.
3. **Given** a user is in the Preferences pane, **When** they look at the "Contributing Usage Data" section, **Then** contextual information is available explaining exactly what is and isn't shared.
4. **Given** the app is in menu bar mode (no dock icon), **When** the user accesses Help, **Then** the help content is still reachable from the popover or menu.

---

### User Story 3 — Contributor Sets Up a Dev Environment (Priority: P3)

A developer wants to contribute to mcp-inator and needs to know: what tools are required, how to build the project, how to run tests, and how to submit a PR.

**Why this priority**: Enables open-source contributions; builds on the README work from US1.

**Independent Test**: A developer with Xcode and Homebrew but no prior knowledge of the project can build and run the app from source using only the contributing guide.

**Acceptance Scenarios**:

1. **Given** a developer clones the repo, **When** they follow the contributing guide, **Then** the app builds successfully with `xcodebuild`.
2. **Given** a developer makes a change, **When** they follow the PR process described in the guide, **Then** they know how to run lint, run tests, bump the version, and open a PR.

---

### Edge Cases

- What if the user is in full menu bar mode (no Application menu)? Help must be reachable from the popover.
- What if the help content references a feature the user's version doesn't have yet? Content should match the current release.
- What if the README screenshots become stale after future UI changes? Screenshots should be marked with the version they were captured from.

## Requirements *(mandatory)*

### Functional Requirements

**README (repo docs)**:

- **FR-001**: The README MUST open with a one-sentence description of what mcp-inator does, followed by a screenshot or GIF of the app in action.
- **FR-002**: The README MUST include a Quick Start section covering: download/install, first launch, and adding a first MCP server.
- **FR-003**: The README MUST include a Features section covering: server management, catalog discovery, agent visibility, Zed/Cursor support, and usage sharing.
- **FR-004**: The README MUST include a Contributing section with: prerequisites (Xcode version, tools), build instructions, test/lint commands, version bump process, and PR checklist.
- **FR-005**: The README MUST include a Privacy section summarizing what usage sharing does and does not collect.

**In-app help**:

- **FR-006**: The app MUST provide a Help entry point accessible from both menu bar mode (popover) and dock mode (Application menu or window).
- **FR-007**: The help content MUST cover: overview of mcp-inator, adding and configuring MCP servers, the catalog and how to install from it, and the usage sharing opt-in (what is collected, how to withdraw).
- **FR-008**: The help view MUST be readable offline — no web requests required to display content.
- **FR-009**: The help content MUST be written for a technical audience (developers using MCP-compatible tools) but must not assume prior knowledge of mcp-inator.
- **FR-010**: The Preferences pane "Contributing Usage Data" section MUST include a brief inline description of what is and isn't shared.

### Key Entities

- **Help content**: Static text displayed inside the app, covering feature explanations. Not fetched from the network.
- **README**: The `README.md` at the repo root, rendered on GitHub.
- **Contributing guide**: Either a section of README or a separate `CONTRIBUTING.md`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A person unfamiliar with the project can read the README and correctly describe what mcp-inator does — verified by informal user test or review.
- **SC-002**: A developer can build the app from source following only the contributing guide, with no additional help needed.
- **SC-003**: All primary in-app help topics (server setup, catalog, usage sharing) are reachable within 2 taps/clicks from any app state.
- **SC-004**: The help view loads and displays fully without a network connection.
- **SC-005**: Zero references to unimplemented or removed features appear in either the README or in-app help.

## Assumptions

- The in-app help will use native SwiftUI views (static text/scroll view), not an embedded web view or external URL.
- Screenshots in the README will show the menu bar mode as the primary view, since that is the default.
- A separate `CONTRIBUTING.md` file is preferred over embedding the contributing guide in the README, to keep the README scannable.
- The help entry point in menu bar mode will be a "Help" button in the popover footer (alongside the existing "Preferences" button).
- In dock mode, help will be accessible via the standard macOS Help menu (Application menu → Help).
- Content will be written in English only; localization is out of scope.
