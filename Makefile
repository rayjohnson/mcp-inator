PROJECT    := mcp-inator.xcodeproj
SCHEME     := mcp-inator
CONFIG     := Debug
APP_BUNDLE := $(shell find ~/Library/Developer/Xcode/DerivedData -name "mcp-inator.app" -path "*/Debug/*" 2>/dev/null | head -1)

CATALOG_SRC := catalog/catalog.json
CATALOG_DST := mcp-inator/Resources/catalog.json

COVERAGE_RESULT := /tmp/mcp-inator-coverage.xcresult
COVERAGE_THRESHOLD := 25

# All Swift sources — Make uses this to detect when xcodegen needs to re-run
# (xcodegen enumerates files into project.pbxproj, so adding/removing a .swift
# file requires regeneration even though project.yml didn't change).
SWIFT_SOURCES := $(shell find mcp-inator mcp-inatorTests -name "*.swift" 2>/dev/null)

.PHONY: build test cover lint run clean generate-version sync-catalog backend-build backend-test

# ── Generated files ──────────────────────────────────────────────────────────
# Make tracks timestamps: recipes run only when a prerequisite is newer than
# the target, so these are no-ops on repeated invocations with no changes.

## Regenerate Xcode project when project.yml or any Swift source file changes.
$(PROJECT)/project.pbxproj: project.yml $(SWIFT_SOURCES)
	xcodegen generate

## Write version.xcconfig from VERSION.
version.xcconfig: VERSION
	@echo "MARKETING_VERSION = $$(cat VERSION | tr -d '[:space:]')" > version.xcconfig
	@echo "CURRENT_PROJECT_VERSION = 1" >> version.xcconfig

## Copy catalog JSON into the app bundle when the source changes.
$(CATALOG_DST): $(CATALOG_SRC)
	cp $(CATALOG_SRC) $(CATALOG_DST)

# ── Phony aliases (kept for backward compatibility and CI scripts) ────────────

## Ensure version.xcconfig is up to date.
generate-version: version.xcconfig

## Ensure catalog bundle resource is up to date.
sync-catalog: $(CATALOG_DST)

# ── Build targets ─────────────────────────────────────────────────────────────

## Build the app.
build: $(PROJECT)/project.pbxproj $(CATALOG_DST) version.xcconfig
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

## Run all tests.
test: $(PROJECT)/project.pbxproj version.xcconfig
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) test

## Run tests with code coverage; fail if below COVERAGE_THRESHOLD.
cover: $(PROJECT)/project.pbxproj version.xcconfig
	rm -rf $(COVERAGE_RESULT)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-enableCodeCoverage YES \
		-resultBundlePath $(COVERAGE_RESULT) \
		test
	@xcrun xccov view --report --json $(COVERAGE_RESULT) 2>/dev/null | \
		python3 -c " \
import sys, json; \
data = json.load(sys.stdin); \
print('Coverage breakdown:'); \
[print(f'  {t[\"name\"]}: {t.get(\"coveredLines\",0)}/{t.get(\"executableLines\",0)} lines ({round(t.get(\"lineCoverage\",0)*100,1)}%)') for t in data.get('targets', [])]; \
app = next((t for t in data.get('targets',[]) if 'mcp-inator' in t['name'] and 'Tests' not in t['name']), None); \
[print(f'    {round(f.get(\"lineCoverage\",0)*100,1):5.1f}%  {f.get(\"coveredLines\",0):4}/{f.get(\"executableLines\",0):4}  {f[\"name\"]}') for f in sorted(app.get('files',[]), key=lambda x: x['name'])] if app else None; \
"; \
	COVERAGE=$$(xcrun xccov view --report --json $(COVERAGE_RESULT) 2>/dev/null | \
		python3 -c " \
import sys, json; \
data = json.load(sys.stdin); \
targets = [t for t in data.get('targets', []) if 'mcp-inator' in t['name'] and 'Tests' not in t['name']]; \
print(round(targets[0]['lineCoverage'] * 100, 1)) if targets else print(0)"); \
	echo "Coverage: $${COVERAGE}% (threshold: $(COVERAGE_THRESHOLD)%)"; \
	python3 -c "import sys; sys.exit(0 if float('$${COVERAGE}') >= $(COVERAGE_THRESHOLD) else 1)" || \
		(echo "ERROR: Coverage $${COVERAGE}% is below threshold $(COVERAGE_THRESHOLD)%"; exit 1)

## Run SwiftLint.
lint:
	swiftlint lint

## Build, then kill any running instance and launch.
run: build
	pkill -x mcp-inator; sleep 1; open "$(APP_BUNDLE)"

## Clean build artifacts.
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean

## Build the Go Cloud Run backend.
backend-build:
	cd backend && go build ./...

## Run Go unit tests for the Cloud Run backend.
backend-test:
	cd backend && go test ./...
