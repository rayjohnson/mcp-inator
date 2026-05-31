# Toolbar Height Bug — Analysis & Second-Opinion Request

## The Bug

In dock mode, the window's title bar / toolbar area changes height as the user switches
sidebar tabs:

- **Servers** → toolbar has a "+" (Add Server) button at `.primaryAction` → taller toolbar
- **Agents** → toolbar has a "Manage" button at `.primaryAction` → taller toolbar
- **Catalog** → no toolbar button → toolbar collapses to a shorter height

The jarring height change makes the window feel broken.

---

## Architecture Context

```
NavigationSplitView
├── sidebar: List (mcp-inator title, three rows)
└── detail: switch selectedSection {
       case .servers:  NavigationStack { ConfigLibraryView() }
       case .agents:   NavigationStack { AgentsView() }
       case .catalog:  NavigationStack { CatalogView() }
    }
```

All three child views set `.navigationTitle(...)` (Servers → "MCP Servers", Agents → "Agents",
Catalog → "Catalog"). None of them set `.toolbar` items themselves (that was centralized in a
previous fix).

The `.toolbar { }` block sits on `NavigationSplitView` in `MainWindowView`.

---

## What We've Tried

### Attempt 1 — AgentsView had its own `.toolbar`

**Original state**: `AgentsView` defined a `.toolbar { ToolbarItem { Button("Manage") } }`
inside its own `NavigationStack`. `CatalogView` had none.

**Result**: Height inconsistency — Agents toolbar was taller than Catalog. This was the
original bug report.

---

### Attempt 2 — Centralize toolbar in MainWindowView + placeholder for Catalog

Removed toolbar from `AgentsView`. Added a single `.toolbar { }` block on
`NavigationSplitView` in `MainWindowView`. To keep consistent height on the Catalog tab,
added a hidden placeholder:

```swift
.toolbar {
    if selectedSection == .servers {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showAddServer = true },
                   label: { Label("Add Server", systemImage: "plus") })
        }
    }
    if selectedSection == .agents {
        ToolbarItem(placement: .primaryAction) {
            Button("Manage") { showManageAgents = true }
        }
    }
    if selectedSection == .catalog {
        ToolbarItem(placement: .primaryAction) {
            Button("", action: {}).hidden()   // placeholder
        }
    }
}
```

**Result**: Height was consistent ✓ — but a **circle artifact** appeared in the top-right
corner of the Catalog tab. macOS applies button chrome to anything inside `ToolbarItem`,
including hidden buttons.

---

### Attempt 3 — Replace hidden Button with Color.clear

```swift
if selectedSection == .catalog {
    ToolbarItem(placement: .primaryAction) {
        Color.clear.frame(width: 28, height: 28)
    }
}
```

**Result**: Still an **oval artifact**. macOS button chrome was applied to `Color.clear` just
as it was to the hidden button.

---

### Attempt 4 — Remove Catalog ToolbarItem entirely (current state)

```swift
.toolbar {
    if selectedSection == .servers {
        ToolbarItem(placement: .primaryAction) { Button(...) }
    }
    if selectedSection == .agents {
        ToolbarItem(placement: .primaryAction) { Button("Manage") { ... } }
    }
    // No catalog case at all
}
```

**Result**: Artifact gone ✓ — but **height shrinks again** on Catalog tab. Back to square one.

---

## What We Know For Certain

1. `ToolbarItem` on macOS applies button chrome (background highlight ring) to **any** view
   placed inside it — including `Button(...).hidden()`, `Color.clear`, and presumably
   `EmptyView()`.

2. The toolbar height on macOS is driven by the **presence of toolbar items** in the
   `NSToolbar`. When SwiftUI places no items, macOS renders a compact/short title bar.
   When at least one item is present, the toolbar is taller.

3. Conditional `if/else` inside `@SceneBuilder` does not compile in this Xcode version.
   That constraint is upstream of `NavigationSplitView` and irrelevant here, but worth
   noting we can't restructure at the Scene level.

4. Conditional `ToolbarItem` blocks inside `.toolbar { }` DO compile — the issue is purely
   visual.

---

## Open Questions for Second Opinion

### Q1 — Is the height driven by NSToolbar item count or by something else?

macOS `NSToolbar` has a fixed height when visible and a different height (or is hidden) when
not. Does SwiftUI's `.toolbar { }` on a `NavigationSplitView` actually toggle the
`NSToolbar` visible/hidden based on whether any `ToolbarItem` views are non-empty? Or is
there a different layout system in play?

If yes: the only way to prevent height collapse is to always have at least one item that
macOS considers "present" but that is visually inert.

### Q2 — Does `.opacity(0).allowsHitTesting(false)` on a Button avoid the chrome?

We've tried `.hidden()` on a Button — that still got chrome. What about:

```swift
Button("", action: {})
    .opacity(0)
    .allowsHitTesting(false)
```

Does `opacity(0)` suppress the macOS button chrome ring, or does it also render the ring at
zero alpha (invisible)? Worth testing.

### Q3 — Does a non-Button view inside ToolbarItem still get chrome?

Tried `Color.clear` — still got oval chrome. What about:
- `EmptyView()`
- `Spacer()`
- `Text(" ")` with `.foregroundColor(.clear)`

Does macOS apply chrome to any of these, or is it specifically triggered by Button-like
content?

### Q4 — Can we prevent the toolbar from collapsing using a window-level API?

The underlying `NSToolbar` has `isVisible` and `displayMode`. Could we reach into the window
via `NSApplication.shared.keyWindow` and force `toolbar?.isVisible = true` regardless of
SwiftUI's item list? This is the kind of "go around SwiftUI" approach that burned us with
the menu bar icon bug, but `NSToolbar.isVisible` may be less tightly managed by SwiftUI than
`NSStatusItem.isVisible`.

### Q5 — Is there a `toolbarBackground` or `toolbarMinHeight` modifier?

Is there a SwiftUI modifier that lets us pin the toolbar to a minimum height, or force the
toolbar visible state, without needing to insert a ToolbarItem? Something like:

```swift
.toolbar(.visible, for: .windowToolbar)
```

(macOS 13+ has `toolbar(_:for:)` visibility API — does that prevent height collapse?)

### Q6 — Could the detail NavigationStack's own toolbar layer be the culprit?

The detail pane uses `NavigationStack { ... }`. On macOS, `NavigationStack` inside
`NavigationSplitView` creates a toolbar layer of its own. Could the height change be driven
by the **inner** NavigationStack toolbar being present/absent rather than the outer
`NavigationSplitView` toolbar? If so, the fix may need to go inside each `NavigationStack`
rather than on the outer `NavigationSplitView`.

### Q7 — Should we place `.toolbar` on each NavigationStack instead?

Rather than one `.toolbar` on `NavigationSplitView`, should we put a consistent toolbar on
each `NavigationStack` in the detail switch? e.g.:

```swift
case .catalog:
    NavigationStack {
        CatalogView()
            ...
    }
    .toolbar {
        // nothing, but the .toolbar modifier itself is present
    }
```

Does the mere presence of `.toolbar { }` with zero items keep the toolbar height stable?

---

## Candidate Fixes to Validate

Listed in order of preference (least invasive first):

**A.** Always-present Button with `opacity(0)` + `allowsHitTesting(false)` instead of
`.hidden()`:

```swift
if selectedSection == .catalog {
    ToolbarItem(placement: .primaryAction) {
        Button("placeholder", action: {})
            .opacity(0)
            .allowsHitTesting(false)
    }
}
```

**B.** `.toolbar(.visible, for: .windowToolbar)` modifier to pin toolbar visible state even
with no items.

**C.** Move `.toolbar` onto each `NavigationStack` in the detail switch instead of on the
outer `NavigationSplitView`, and include an empty `.toolbar { }` on the Catalog stack.

**D.** Always emit all three `ToolbarItem`s but control their opacity/interaction:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button(action: { showAddServer = true },
               label: { Label("Add Server", systemImage: "plus") })
        .opacity(selectedSection == .servers ? 1 : 0)
        .allowsHitTesting(selectedSection == .servers)
    }
    ToolbarItem(placement: .primaryAction) {
        Button("Manage") { showManageAgents = true }
        .opacity(selectedSection == .agents ? 1 : 0)
        .allowsHitTesting(selectedSection == .agents)
    }
}
```

Always two items present; only the correct one is interactive/visible. Avoids the
"no items → height collapse" problem entirely, and avoids the "placeholder gets chrome"
problem because real Buttons with `opacity(0)` may suppress their chrome.

---

## Files Involved

| File | Role |
|------|------|
| `mcp-inator/UI/MainWindowView.swift` | Owns `.toolbar { }` block on `NavigationSplitView` |
| `mcp-inator/UI/AgentsView.swift` | Has `@Binding var showManageAgents: Bool` (no toolbar) |
| `mcp-inator/UI/ConfigLibraryView.swift` | Sets `.navigationTitle("MCP Servers")`, no toolbar |
| `mcp-inator/UI/CatalogView.swift` | Sets `.navigationTitle("Catalog")`, no toolbar |
