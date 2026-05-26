<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan at
`specs/001-mcp-config-management/plan.md`.
<!-- SPECKIT END -->

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
