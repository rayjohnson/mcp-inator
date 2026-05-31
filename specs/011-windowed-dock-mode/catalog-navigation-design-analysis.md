# Catalog Navigation — Design Analysis & Second-Opinion Request

## The Problem

In dock mode, clicking a catalog entry pushes `CatalogEntryDetailView` onto the
`NavigationStack` inside the Catalog tab's detail column. There is no system-provided
back button on macOS — the user was trapped with no way to return to the catalog list.

The current fix adds an explicit `‹ Back` button via `@Environment(\.dismiss)` + a
`ToolbarItem(placement: .navigation)`. It works, but it feels like an iOS pattern grafted
onto macOS.

---

## Current Architecture

```
NavigationSplitView
├── sidebar: List (Servers / Agents / Catalog rows)
└── detail: switch selectedSection {
       case .catalog:
           NavigationStack {
               CatalogView()           ← list of catalog entries
                   .searchable(...)    ← search field in toolbar
           }
   }
```

`CatalogView` uses `NavigationLink(destination: CatalogEntryDetailView(...))` to push
the detail. This works identically in menu bar mode (tab view) and dock mode (split view),
which is why it wasn't noticed until dock mode arrived.

---

## What macOS HIG Says

The Human Interface Guidelines describe three navigation patterns for macOS:

1. **Navigation split view** (sidebar + content + optional detail column): The canonical
   pattern for document and content browsers. Clicking a row in the content column updates
   the detail column in place. No navigation stack, no back button. Used by: Finder,
   Mail, Music, Podcasts, App Store.

2. **Modal sheets**: For focused tasks that the user must complete or explicitly cancel
   before returning to the main flow. The sheet slides up over the window. Used for
   editing, configuration, confirmation. Dismissed with a Done/Cancel/Close button.

3. **Navigation stack (push/pop)**: Used on iOS and in Settings on macOS 13+ (which is a
   Catalyst port). On native macOS it appears in some developer tools (Xcode's navigator
   push behavior). HIG does not call this out as a preferred pattern for macOS content
   browsers.

The current implementation uses pattern 3, which feels out of place on macOS for a
read-and-browse catalog.

---

## Option A — Three-Column NavigationSplitView (Most Mac-idiomatic)

**What it looks like:**
```
┌─────────────┬──────────────────┬────────────────────────────┐
│  mcp-inator │   Catalog list   │   CatalogEntryDetailView   │
│  ─────────  │  ─────────────   │  ──────────────────────    │
│  Servers    │  [search bar]    │  GitHub MCP               │
│  Agents     │  Trending        │  ★ 1.2K  •  3 days ago    │
│  Catalog    │  › GitHub MCP    │                            │
│             │  › Slack MCP     │  [detail content]          │
│             │  › ...           │                            │
│             │                  │  [Add to Library]          │
└─────────────┴──────────────────┴────────────────────────────┘
```

The left column stays as-is (Servers / Agents / Catalog). Clicking "Catalog" shows the
catalog list in the middle column. Clicking an entry shows the detail in the right column.
No navigation stack, no back button, no push/pop animation.

**Pros:**
- Follows the macOS HIG split-view pattern exactly
- Detail is always visible alongside the list (no context switch)
- Persistent selection — the user can see which entry they're looking at
- Consistent with Finder, Music, App Store

**Cons:**
- Significant refactor: `CatalogView` needs to split into a list component and a detail
  component; `MainWindowView` needs to manage a `selectedEntry` binding
- The other two tabs (Servers, Agents) also use `NavigationStack` push — this would create
  an inconsistency in navigation model between tabs unless those are also converted
- Minimum window width may need to increase to accommodate three columns comfortably

**Files that change:**
- `MainWindowView.swift` — add `selectedCatalogEntry` state; switch Catalog case to a
  two-column split (content + detail)
- `CatalogView.swift` — remove `NavigationLink`; emit a selection callback or binding
- `CatalogEntryDetailView.swift` — remove `dismiss` back button; add empty-selection state

---

## Option B — Sheet Presentation (Smaller Change, Still Native)

**What it looks like:**
Clicking a catalog entry slides a sheet up over the main window. The sheet has a close
button (✕ or "Done") in its toolbar. The user inspects/adds the entry, then dismisses.

```
┌──────────────────────────────────────────────────────────────┐
│  main window (blurred behind)                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  GitHub MCP                                    [✕]     │  │
│  │  ────────────────────────────────────────────────────  │  │
│  │  [detail content]                                      │  │
│  │                                                        │  │
│  │                               [Add to Library]         │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**Pros:**
- Small refactor: change `NavigationLink` to a `.sheet(isPresented:)` call
- No back button needed — sheet has a standard dismiss affordance
- Modal framing is appropriate for "inspect this item before adding it"
- Works identically whether invoked from the menu bar popover or dock mode window

**Cons:**
- Modal: blocks access to the catalog list while the detail is open (can't compare two
  entries without dismissing)
- Less discoverable than a split view — user can't see both list and detail simultaneously
- Slightly heavier UX for a read-mostly browse workflow

**Files that change:**
- `CatalogView.swift` — replace `NavigationLink` with `@State var selectedEntry` +
  `.sheet(item: $selectedEntry)`
- `CatalogEntryDetailView.swift` — remove `dismiss` back button; add a Done/Close button
  (or rely on the sheet's swipe-to-dismiss)
- Also applies to `AlternativesRow` in the same file

---

## Option C — Keep NavigationStack + Explicit Back Button (Status Quo)

The current fix: `ToolbarItem(placement: .navigation)` with a `‹ Back` chevron that calls
`dismiss()`.

**Pros:**
- Already implemented and working
- Familiar to users who come from iOS/iPadOS

**Cons:**
- Not idiomatic macOS — the HIG does not endorse push navigation for content browsers
- Back button position (toolbar leading edge) can conflict with window controls on macOS
- If the window is narrow, the back button may overlap with the window title
- Inconsistent with how Servers and Agents handle their detail views (they use
  `NavigationLink` too, so they have the same hidden problem — nobody noticed because
  those detail views have more toolbar controls that make the navigation context clearer)

---

## The Hidden Same-Problem in Servers and Agents

`AgentsView` navigates to `AgentListView` via `NavigationLink`. `AgentListView` now has
the same explicit back button fix applied.

`ConfigLibraryView` (Servers tab) also uses `NavigationLink` to push `AddEditConfigView`
or detail views. These all have the same potential back-navigation gap in dock mode.

Whichever pattern is chosen for Catalog should ideally be applied consistently to all
three tabs in dock mode, otherwise the app will feel inconsistent.

---

## Questions for Second Opinion

**Q1 — Three-column vs sheet for a catalog browser?**
Is Option A (three-column split) worth the refactor cost for a catalog that is primarily
browse-and-add rather than constantly-referring-to? Or is Option B (sheet) more
appropriate for the "inspect before committing" workflow?

**Q2 — Consistency across all three tabs?**
Should Servers / Agents / Catalog all converge on the same navigation model in dock mode?
If so, which model scales best across all three? Servers already has a list-detail
mental model (list of configs → edit one config). Agents also has list-detail (list of
agents → agent config view). Catalog has list-detail-action (list → detail → add to
library).

**Q3 — Is the NavigationStack push pattern acceptable on macOS for this use case?**
Some modern Mac apps (particularly those with cross-platform SwiftUI codebases) do use
NavigationStack push with explicit back buttons. Is this "good enough" given the
menu-bar-mode origin of the app, or should it be fixed before 1.0?

**Q4 — Does the menu bar popover use of NavigationStack matter?**
The same `CatalogView` is used in both the menu bar popover (tab view, small 420px wide
panel) and the dock mode window (full NavigationSplitView). The menu bar popover benefits
from the push navigation because screen real estate is tiny. A three-column split would
be wrong for the popover. If different layouts are used per mode, how should that be
structured?

---

## Recommendation

If the goal is to ship a polished Mac experience: **Option A** (three-column split) for
Catalog, with the understanding that Servers and Agents should follow the same pattern
eventually.

If the goal is to ship quickly and improve incrementally: **Option B** (sheet) for now,
since it's a small change, clearly native macOS, and can be shipped as part of this PR.
The three-column refactor can be a separate feature.

The current Option C (back button) is a reasonable stopgap but should not be considered
the final answer.
