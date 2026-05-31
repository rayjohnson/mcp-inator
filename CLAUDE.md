<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan at
`specs/011-windowed-dock-mode/plan.md`.
<!-- SPECKIT END -->

## Before Every PR (required)

1. `make lint` — fix all SwiftLint warnings before proceeding
2. `make cover` — tests must pass and coverage must meet threshold
3. Bump the patch version in `VERSION` (e.g. `0.4.0` → `0.4.1`). Just edit the file directly — no need to look at git tags.
4. Update `RELEASE_NOTES.md` with what changed

Do all four before creating or updating a PR. No exceptions.

## Build & Run

Build:
```
xcodebuild -project mcp-inator.xcodeproj -scheme mcp-inator -configuration Debug build
```

The built app lands in DerivedData:
```
~/Library/Developer/Xcode/DerivedData/mcp-inator-arfxwbxlqszljmbfuhidccpxmwhl/Build/Products/Debug/mcp-inator.app
```

Launch (always kill the running instance first — it's a menu bar app that stays resident):
```
pkill -x mcp-inator; sleep 1; open ~/Library/Developer/Xcode/DerivedData/mcp-inator-arfxwbxlqszljmbfuhidccpxmwhl/Build/Products/Debug/mcp-inator.app
```

## App Architecture: Two-Mode Design

The app runs in two mutually exclusive modes controlled by `showInDock` (`@AppStorage`):

- **Menu bar mode** (default): `NSApp` activation policy is `.accessory`. No standard Application menu exists. The `MenuBarExtra` popover is the entire UI.
- **Dock mode**: activation policy is `.regular`. A standard `NSWindow` (via `MainWindowController`) is the primary UI, and macOS provides a full Application menu.

### Single preferences window

`PreferencesWindowController` is the **only** preferences mechanism. There is intentionally **no** SwiftUI `Settings` scene — it creates a competing "mcp-inator Settings" window that duplicates "Preferences" and cannot be suppressed without re-architecting.

- Menu bar mode: footer "Preferences..." button → `openPreferencesWindow` env → `PreferencesWindowController`
- Dock mode: Application menu "Preferences..." / Cmd+, → `CommandGroup(replacing: .appSettings)` → `PreferencesWindowController`

### Application menu commands (dock mode only)

`CommandGroup` replacements **must be attached to `MenuBarExtra`**, not to any other scene. Attaching `.commands` to a `Settings` scene strips the standard Application menu (Quit, Hide, etc.) and leaves only the replaced items.

In menu bar mode, `CommandGroup` has no effect (no Application menu exists), so the same `.commands` block is safe in both modes.
