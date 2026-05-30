# Feature Specification: Windowed App Mode with Menu Bar Toggle

**Feature Branch**: `011-windowed-dock-mode`

**Created**: 2026-05-30

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Dock Mode (Priority: P1)

A user who spends significant time in mcp-inator — adding many servers, browsing the catalog, managing agents — wants the app to behave like a standard macOS desktop app. They go to Settings, toggle "Show in Dock," and the app immediately gains a dock icon and Cmd+Tab access. A full resizable window opens. From that point on, launching the app opens this window. The popover is gone; the menu bar icon now raises the window instead.

**Why this priority**: This is the core deliverable. Everything else depends on the windowed layout existing.

**Independent Test**: Toggle "Show in Dock" on; verify dock icon appears, Cmd+Tab works, and a resizable window opens without restarting the app.

**Acceptance Scenarios**:

1. **Given** the app is in menu bar mode, **When** the user toggles "Show in Dock" in Settings, **Then** a dock icon appears immediately and a resizable main window opens without restarting.
2. **Given** dock mode is active, **When** the user clicks the menu bar icon, **Then** the existing window is focused (or re-opened if closed) — no popover appears.
3. **Given** dock mode is active, **When** the user presses Cmd+Tab, **Then** mcp-inator appears in the app switcher.
4. **Given** dock mode is active, **When** the user quits and relaunches the app, **Then** the main window opens automatically and dock mode is still active.
5. **Given** dock mode is active, **When** the user toggles "Show in Dock" off, **Then** the dock icon disappears, the window closes, and the app returns to menu bar popover behavior — all without restarting.

---

### User Story 2 - Windowed Layout Navigation (Priority: P2)

A user in dock mode opens the main window and navigates between Servers, Agents, Catalog, and Settings using a sidebar. Each section fills the right-hand content area. The window can be resized and the last size and position are remembered across launches.

**Why this priority**: The windowed layout must be usable and feel like a real macOS app, not just a popover in a window frame.

**Independent Test**: In dock mode, open the window and verify all four sections are accessible via the sidebar, content fills the available space correctly, and window size/position persists after quit and relaunch.

**Acceptance Scenarios**:

1. **Given** the main window is open, **When** the user clicks a sidebar item (Servers, Agents, Catalog, Settings), **Then** the correct content view appears in the detail area.
2. **Given** the main window is open, **When** the user resizes the window, **Then** content reflows appropriately and the window respects a minimum size (no smaller than 800×500 points).
3. **Given** the user has resized and repositioned the window, **When** they quit and relaunch, **Then** the window reopens at the same size and position.
4. **Given** the main window is open, **When** the user performs a primary action (e.g., Add Server), **Then** the action is accessible without navigating to the menu bar popover.

---

### User Story 3 - Return to Menu Bar Mode (Priority: P3)

A user who enabled dock mode decides they prefer the lighter menu bar experience. They toggle "Show in Dock" off and the app immediately reverts: dock icon gone, window closed, menu bar icon opens the popover again.

**Why this priority**: Reversibility is important for user trust; the preference must truly be a toggle, not a one-way migration.

**Independent Test**: With dock mode active, toggle it off and confirm the app fully reverts to menu bar-only behavior in the same session.

**Acceptance Scenarios**:

1. **Given** dock mode is active, **When** "Show in Dock" is toggled off, **Then** the dock icon disappears immediately.
2. **Given** dock mode was just turned off, **When** the user clicks the menu bar icon, **Then** the popover opens as in the original menu bar mode.
3. **Given** the user toggled dock mode off then on multiple times in one session, **Then** the app remains stable with no duplicate windows or icons.

---

### Edge Cases

- What happens when the user closes the main window in dock mode (red X)? The window closes but the app keeps running (menu bar icon remains). Clicking the menu bar icon or dock icon re-opens the window.
- What happens when dock mode is toggled while a sheet or modal is open? The sheet should be dismissed first, or the toggle should wait until the sheet closes.
- What if the saved window position is off-screen (e.g., after disconnecting an external monitor)? The window should open on the primary display at a sensible default position.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST provide a "Show in Dock" toggle in the Settings section, defaulting to off.
- **FR-002**: The preference MUST be persisted across app launches.
- **FR-003**: Toggling "Show in Dock" on MUST immediately add a dock icon and enable Cmd+Tab access without requiring a restart.
- **FR-004**: Toggling "Show in Dock" on MUST open the main window automatically if it is not already open.
- **FR-005**: In dock mode, clicking the menu bar icon MUST focus the existing main window (or reopen it if closed) rather than showing a popover.
- **FR-006**: Toggling "Show in Dock" off MUST immediately remove the dock icon and restore popover behavior for the menu bar icon, without requiring a restart.
- **FR-007**: The main window MUST contain a sidebar listing all major sections: Servers, Agents, Catalog, Settings.
- **FR-008**: The main window MUST have a minimum size of 800×500 points.
- **FR-009**: The main window's size and position MUST be remembered and restored on next launch.
- **FR-010**: All content views (server list, catalog, agent list, settings) MUST function correctly in both the popover and windowed contexts without duplication of view code.
- **FR-011**: In dock mode, when the user quits and relaunches the app, the main window MUST open automatically.
- **FR-012**: Closing the main window (red X) in dock mode MUST keep the app running; the window can be reopened via the menu bar icon or dock icon.
- **FR-013**: If the saved window position would place the window fully off-screen, the window MUST open at a safe default position on the primary display.

### Key Entities

- **AppMode**: The current presentation mode of the app — menu bar only vs. dock + windowed. Stored as a boolean preference (`showInDock`).
- **WindowState**: The persisted size and position of the main window. Restored on launch in dock mode.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Toggling "Show in Dock" on produces a visible dock icon and an open window in under 1 second.
- **SC-002**: Toggling "Show in Dock" off removes the dock icon and restores popover behavior in under 1 second.
- **SC-003**: All existing features (add/edit server, catalog browse, agent management) are fully accessible in the windowed layout with no regression.
- **SC-004**: Window size and position are correctly restored in 100% of relaunch scenarios (assuming the position is on-screen).
- **SC-005**: Toggling between modes five times in a single session produces no crashes, duplicate windows, or UI artifacts.

## Assumptions

- The menu bar icon remains visible in dock mode (hiding it is explicitly out of scope for this feature).
- The windowed layout uses a two-column sidebar+detail design (not three-column); a third column can be added later if needed.
- Toolbar actions (Add Server, etc.) will be surfaced in the window toolbar in dock mode, replacing the popover header buttons.
- The same SwiftUI content views are reused in both modes; only the top-level container (popover vs. NavigationSplitView window) differs.
- No migration prompt is shown to existing users; dock mode is strictly opt-in.
- The Settings section is accessible in both modes (inside the popover in menu bar mode, via the sidebar in dock mode).
