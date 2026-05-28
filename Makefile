PROJECT    := mcp-inator.xcodeproj
SCHEME     := mcp-inator
CONFIG     := Debug
APP_BUNDLE := $(shell find ~/Library/Developer/Xcode/DerivedData -name "mcp-inator.app" -path "*/Debug/*" 2>/dev/null | head -1)

CATALOG_SRC := catalog/catalog.json
CATALOG_DST := mcp-inator/Resources/catalog.json

.PHONY: build test lint run clean sync-catalog generate-version

## Write version.xcconfig from VERSION (used by Xcode build settings)
generate-version:
	@echo "MARKETING_VERSION = $$(cat VERSION | tr -d '[:space:]')" > version.xcconfig
	@echo "CURRENT_PROJECT_VERSION = 1" >> version.xcconfig

## Build the app (syncs catalog and version first)
build: sync-catalog generate-version
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

## Run all tests
test: generate-version
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
