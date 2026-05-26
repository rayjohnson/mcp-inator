PROJECT    := mcp-inator.xcodeproj
SCHEME     := mcp-inator
CONFIG     := Debug
APP_BUNDLE := $(shell find ~/Library/Developer/Xcode/DerivedData -name "mcp-inator.app" -path "*/Debug/*" 2>/dev/null | head -1)

CATALOG_SRC := catalog/catalog.json
CATALOG_DST := mcp-inator/Resources/catalog.json

.PHONY: build test lint run clean sync-catalog

## Build the app (syncs catalog first)
build: sync-catalog
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

## Run all tests
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) test

## Run SwiftLint
lint:
	swiftlint lint

## Build, then kill any running instance and launch
run: build
	pkill -x mcp-inator; sleep 1; open "$(APP_BUNDLE)"

## Copy catalog source to bundle resource
sync-catalog:
	cp $(CATALOG_SRC) $(CATALOG_DST)

## Clean build artifacts
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
