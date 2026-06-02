# Research: In-App Help & README Overhaul

## Decision 1: In-app help rendering approach

**Decision**: Static SwiftUI `ScrollView` with `Text`/`VStack` content — no `WKWebView`, no URL fetch.

**Rationale**: Keeps the feature offline-capable by default, avoids adding a new dependency, and matches the existing app's SwiftUI-first codebase. The help content is short enough that a single scrollable view per topic (or a simple tab/section structure) is sufficient.

**Alternatives considered**:
- `WKWebView` loading a local HTML bundle — adds complexity, harder to style to match app theme, overkill for static content
- External URL — violates the offline requirement (FR-008)

## Decision 2: Help entry point in menu bar mode

**Decision**: Add a "Help…" button to the `MenuBarView` popover footer, alongside the existing "About mcp-inator…" and "Preferences…" buttons. Opens `HelpView` in a new `NSWindow` managed by a `HelpWindowController` (mirrors the existing `PreferencesWindowController` pattern).

**Rationale**: The footer is the established home for non-primary actions in the popover. Reusing the window controller pattern keeps architecture consistent (Constitution I).

**Alternatives considered**:
- Sheet within the popover — constrained height, hard to read long content
- Inline expand within popover — same constraint; help content is too long

## Decision 3: Help entry point in dock mode

**Decision**: Add a `CommandGroup(after: .help)` entry — "mcp-inator Help…" — in the Application menu's Help submenu. Same `HelpWindowController` as menu bar mode.

**Rationale**: macOS convention; dock-mode users expect Help in the Help menu. Reusing the same window controller means one code path.

## Decision 4: CONTRIBUTING.md vs README section

**Decision**: Separate `CONTRIBUTING.md` at repo root, linked from README.

**Rationale**: Keeps the README scannable for end users. GitHub renders a "Contributing" link automatically when `CONTRIBUTING.md` exists.

## Decision 5: Screenshots

**Decision**: Capture menu bar mode (popover open) showing the server list as the hero screenshot; add a second screenshot showing the catalog view. Store in `docs/images/`. Annotate filenames with the version (e.g., `menubar-v0.5.0.png`).

**Rationale**: Menu bar mode is the default and primary UX. Versioned filenames make it obvious when screenshots are stale.

## No open unknowns

All NEEDS CLARIFICATION items from Technical Context were resolved above. No external research required.
