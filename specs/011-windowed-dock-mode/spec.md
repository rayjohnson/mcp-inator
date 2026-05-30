# Feature Specification: Windowed App Mode with Menu Bar Toggle

**Feature Branch**: `011-windowed-dock-mode`

**Created**: 2026-05-30

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Dock Mode (Priority: P1)

A user who spends significant time in mcp-inator — adding many servers, browsing the catalog, managing agents — wants the app to behave like a standard macOS desktop app. They open Preferences (Cmd+,), toggle "Show in Dock," and the app immediately gains a dock icon and Cmd+Tab access. The menu bar icon disappears. A full resizable window opens automatically. From that point on, launching the app opens this window directly.

**Why this priority**: This is the core deliverable. Everything else depends on the windowed layout existing.

**Independent Test**: Toggle "Show in Dock" on; verify dock icon appears, menu bar icon disappears, Cmd+Tab works, and a resizable window opens — all without restarting.

**Acceptance Scenarios**:

1. **Given** the app is in menu bar mode, **When** the user toggles "Show in Dock" in Preferences, **Then** a dock icon appears immediately, the menu bar icon disappears, and a resizable main window opens — no restart required.
2. **Given** dock mode is active, **When** the user presses Cmd+Tab, **Then** mcp-inator appears in the app switcher.
3. **Given** dock mode is active, **When** the user quits and relaunches the app, **Then** the main window opens automatically and dock mode is still active.
4. **Given** dock mode is active, **When** the user toggles "Show in Dock" off in Preferences, **Then** the dock icon disappears, the window closes, the menu bar icon reappears, and the app returns to popover behavior — no restart required.

---

### User Story 2 - Windowed Layout Navigation (Priority: P2)

A user in dock mode navigates between Servers, Agents, and Catalog using a sidebar. Each section fills the right-hand content area. The window can be resized and the last size and position are remembered across launches. Preferences are accessed via Cmd+, as a separate window.

**Why this priority**: The windowed layout must feel like a real macOS app.

**Independent Test**: In dock mode, verify all three sections are accessible via the sidebar, Preferences opens via Cmd+, as a separate window, content fills the available space, and window size/position persists after quit and relaunch.

**Acceptance Scenarios**:

1. **Given** the main window is open, **When** the user clicks a sidebar item (Servers, Agents, Catalog), **Then** the correct content view appears in the detail area.
2. **Given** the main window is open, **When** the user presses Cmd+,, **Then** a separate Preferences window opens containing the "Show in Dock" toggle, the "Launch at Login" toggle, and other app settings.
3. **Given** the main window is open, **When** the user resizes the window, **Then** content reflows appropriately and the window respects a minimum size of 800×500 points.
4. **Given** the user has resized and repositioned the window, **When** they quit and relaunch, **Then** the window reopens at the same size and position.
5. **Given** the main window is open, **When** the user selects "About mcp-inator" from the application menu, **Then** the About panel appears.

---

### User Story 3 - Return to Menu Bar Mode (Priority: P3)

A user who enabled dock mode decides they prefer the lighter menu bar experience. They open Preferences (Cmd+,), toggle "Show in Dock" off, and the app immediately reverts: dock icon gone, window closed, menu bar icon reappears, clicking it opens the popover again.

**Why this priority**: Reversibility is important for user trust; the preference must truly be a toggle, not a one-way migration.

**Independent Test**: With dock mode active, toggle it off and confirm the app fully reverts to menu bar-only behavior in the same session.

**Acceptance Scenarios**:

1. **Given** dock mode is active, **When** "Show in Dock" is toggled off in Preferences, **Then** the dock icon disappears, the window closes, and the menu bar icon reappears — all immediately.
2. **Given** dock mode was just turned off, **When** the user clicks the menu bar icon, **Then** the popover opens as in the original menu bar mode.
3. **Given** the user toggles dock mode off then on multiple times in one session, **Then** the app remains stable with no duplicate windows or icons.

---

### Edge Cases

- What happens when the user closes the main window in dock mode (red X)? Closing the window quits the app (no hidden background process).
- What happens when dock mode is toggled while a sheet or modal is open? The sheet is dismissed before the mode switch completes.
- What if the saved window position is off-screen (e.g., after disconnecting an external monitor)? The window opens at a safe default position on the primary display.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST provide a "Show in Dock" toggle in a dedicated Preferences window, defaulting to off.
- **FR-002**: The preference MUST be persisted across app launches.
- **FR-003**: Toggling "Show in Dock" on MUST immediately add a dock icon and enable Cmd+Tab access without requiring a restart.
- **FR-004**: Toggling "Show in Dock" on MUST remove the menu bar icon and open the main window automatically.
- **FR-005**: Toggling "Show in Dock" off MUST immediately remove the dock icon, close the main window, and restore the menu bar icon and popover behavior — without requiring a restart.
- **FR-006**: In dock mode, closing the main window (red X) MUST quit the application.
- **FR-007**: The app MUST provide a Preferences window accessible via Cmd+, in dock mode, containing at minimum the "Show in Dock" toggle, a "Launch at Login" toggle, and any other existing app settings.
- **FR-007a**: The "Launch at Login" toggle MUST register or unregister the app as a login item immediately when toggled, persisted across launches.
- **FR-008**: The app MUST display an About panel accessible from the application menu in dock mode.
- **FR-009**: The main window MUST contain a sidebar with three sections: Servers, Agents, Catalog. Servers is selected by default.
- **FR-010**: The main window MUST have a minimum size of 800×500 points.
- **FR-011**: The main window's size and position MUST be remembered and restored on next launch.
- **FR-012**: In dock mode, when the user quits and relaunches the app, the main window MUST open automatically.
- **FR-013**: If the saved window position would place the window fully off-screen, the window MUST open at a safe default position on the primary display.
- **FR-014**: All content views (server list, catalog, agent list) MUST function correctly in both the popover and windowed contexts without duplication of view code.

### Key Entities

- **AppMode**: The current presentation mode — menu bar only vs. dock + windowed. Stored as a boolean preference (`showInDock`).
- **WindowState**: The persisted size and position of the main window. Restored on launch in dock mode.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Toggling "Show in Dock" on produces a visible dock icon, no menu bar icon, and an open window in under 1 second.
- **SC-002**: Toggling "Show in Dock" off removes the dock icon, restores the menu bar icon, and closes the window in under 1 second.
- **SC-003**: All existing features (add/edit server, catalog browse, agent management) are fully accessible in the windowed layout with no regression.
- **SC-004**: Window size and position are correctly restored in 100% of relaunch scenarios (assuming the position is on-screen).
- **SC-005**: Toggling between modes five times in a single session produces no crashes, duplicate windows, or UI artifacts.

## Assumptions

- The windowed layout uses a two-column sidebar+detail design; a third column can be added later if needed.
- The same SwiftUI content views are reused in both modes; only the top-level container (popover vs. window) differs.
- No migration prompt is shown to existing users; dock mode is strictly opt-in.
- The Preferences window contains the existing settings content (previously in the Settings tab of the popover) plus the "Show in Dock" toggle.
- Launch at Login is in scope and will be included in the Preferences window.
- The macOS application menu in dock mode includes at minimum: About mcp-inator, Settings/Preferences (Cmd+,), and Quit (Cmd+Q).
