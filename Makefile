PROJECT    := mcp-inator.xcodeproj
SCHEME     := mcp-inator
CONFIG     := Debug
APP_BUNDLE := $(shell find ~/Library/Developer/Xcode/DerivedData -name "mcp-inator.app" -path "*/Debug/*" 2>/dev/null | head -1)

CATALOG_SRC := catalog/catalog.json
CATALOG_DST := mcp-inator/Resources/catalog.json

COVERAGE_RESULT := /tmp/mcp-inator-coverage.xcresult
COVERAGE_THRESHOLD := 30

.PHONY: build test cover lint run clean sync-catalog generate-version

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

## Run tests with code coverage; fail if below COVERAGE_THRESHOLD
cover: generate-version
	rm -rf $(COVERAGE_RESULT)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-enableCodeCoverage YES \
		-resultBundlePath $(COVERAGE_RESULT) \
		test
	@COVERAGE=$$(xcrun xccov view --report --json $(COVERAGE_RESULT) 2>/dev/null | \
		python3 -c " \
import sys, json; \
data = json.load(sys.stdin); \
targets = [t for t in data.get('targets', []) if 'mcp-inator' in t['name'] and 'Tests' not in t['name']]; \
print(round(targets[0]['lineCoverage'] * 100, 1)) if targets else print(0)"); \
	echo "Coverage: $${COVERAGE}% (threshold: $(COVERAGE_THRESHOLD)%)"; \
	python3 -c "import sys; sys.exit(0 if float('$${COVERAGE}') >= $(COVERAGE_THRESHOLD) else 1)" || \
		(echo "ERROR: Coverage $${COVERAGE}% is below threshold $(COVERAGE_THRESHOLD)%"; exit 1)

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
