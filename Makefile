CONFIG = Debug

DERIVED_DATA_PATH = ~/.derivedData/$(CONFIG)
TEMP_COVERAGE_DIR := temp_coverage

PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS,Watch)

PLATFORM = IOS
DESTINATION = platform="$(PLATFORM_$(PLATFORM))"

PLATFORM_ID = $(shell echo "$(DESTINATION)" | sed -E "s/.+,id=(.+)/\1/")

SCHEME = Supabase

WORKSPACE = Supabase.xcworkspace

XCODEBUILD_ARGUMENT = test

XCODEBUILD_FLAGS = \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	-destination $(DESTINATION) \
	-scheme "$(SCHEME)" \
	-skipMacroValidation \
	-workspace $(WORKSPACE)

XCODEBUILD_COMMAND = xcodebuild $(XCODEBUILD_ARGUMENT) $(XCODEBUILD_FLAGS)

ifneq ($(strip $(shell which xcbeautify)),)
	XCODEBUILD = set -o pipefail && $(XCODEBUILD_COMMAND) | xcbeautify
else
	XCODEBUILD = $(XCODEBUILD_COMMAND)
endif

TEST_RUNNER_CI = $(CI)

warm-simulator:
	@test "$(PLATFORM_ID)" != "" \
		&& xcrun simctl boot $(PLATFORM_ID) \
		&& open -a Simulator --args -CurrentDeviceUDID $(PLATFORM_ID) \
		|| exit 0

xcodebuild: warm-simulator
	$(XCODEBUILD)

test-integration:
	cd Tests/IntegrationTests && supabase start && supabase db reset
	swift test --filter IntegrationTests
	cd Tests/IntegrationTests && supabase stop

build-for-library-evolution:
	swift build \
		-q \
		-c release \
		--target Supabase \
		-Xswiftc -emit-module-interface \
		-Xswiftc -enable-library-evolution

DOC_WARNINGS = $(shell xcodebuild clean docbuild \
	-scheme Supabase \
	-destination platform="$(PLATFORM_MACOS)" \
	-quiet \
	2>&1 \
	| grep "couldn't be resolved to known documentation" \
	| sed 's|$(PWD)|.|g' \
	| tr '\n' '\1')
test-docs:
	@test "$(DOC_WARNINGS)" = "" \
		|| (echo "xcodebuild docbuild failed:\n\n$(DOC_WARNINGS)" | tr '\1' '\n' \
		&& exit 1)

format:
	find . \
		-path '*/Documentation/docc' -prune -o \
		-name '*.swift' \
		-not -path '*/.*' -print0 \
		| xargs -0 swift format --ignore-unparsable-files --in-place

.PHONY: build-for-library-evolution format warm-simulator xcodebuild test-docs test-integration

.PHONY: coverage
coverage:
	@DERIVED_DATA_PATH=$(DERIVED_DATA_PATH) ./scripts/generate-coverage.sh

define udid_for
$(shell xcrun simctl list --json devices available '$(1)' | jq -r '[.devices|to_entries|sort_by(.key)|reverse|.[].value|select(length > 0)|.[0]][0].udid')
endef

# ── Code generation ────────────────────────────────────────────────────────────

.PHONY: sync-models generate-smithy generate-swift-storage generate-swift-functions generate-swift-postgrest generate check-generate check-swift-openapi-generator

# Path to a local checkout of supabase/sdk (override with SDK_REPO=/path/to/sdk)
SDK_REPO ?= $(shell git rev-parse --show-toplevel)/../../sdk

check-swift-openapi-generator:
	@which swift-openapi-generator > /dev/null 2>&1 || \
	  (echo "Error: swift-openapi-generator not found in PATH. Build from source: https://github.com/apple/swift-openapi-generator" && exit 1)

# Copy pre-generated OpenAPI artifacts from supabase/sdk (no Smithy install needed)
sync-models:
	@test -d "$(SDK_REPO)/smithy/openapi" || \
	  (echo "Error: supabase/sdk repo not found at $(SDK_REPO). Clone it or set SDK_REPO=/path/to/sdk" && exit 1)
	cp "$(SDK_REPO)/smithy/openapi/StorageService.openapi.json" smithy/output/openapi/StorageService.openapi.json
	cp "$(SDK_REPO)/smithy/openapi/FunctionsService.openapi.json" smithy/output/openapi/FunctionsService.openapi.json
	cp "$(SDK_REPO)/smithy/openapi/DatabaseService.openapi.json" smithy/output/openapi/DatabaseService.openapi.json
	python3 smithy/patch-openapi.py smithy/output/openapi/StorageService.openapi.json
	@echo "Models synced from $(SDK_REPO)"

# Build Smithy models locally (requires Smithy CLI; use sync-models instead if not installed)
generate-smithy:
	cd "$(SDK_REPO)/smithy" && smithy build
	cp "$(SDK_REPO)/smithy/build/smithy/storage-openapi/openapi/StorageService.openapi.json" smithy/output/openapi/StorageService.openapi.json
	cp "$(SDK_REPO)/smithy/build/smithy/functions-openapi/openapi/FunctionsService.openapi.json" smithy/output/openapi/FunctionsService.openapi.json
	cp "$(SDK_REPO)/smithy/build/smithy/database-openapi/openapi/DatabaseService.openapi.json" smithy/output/openapi/DatabaseService.openapi.json
	python3 smithy/patch-openapi.py smithy/output/openapi/StorageService.openapi.json

generate-swift-storage: check-swift-openapi-generator
	swift-openapi-generator generate \
	  --config Sources/Storage/openapi-generator-config.yaml \
	  --output-directory Sources/Storage/Generated \
	  smithy/output/openapi/StorageService.openapi.json

generate-swift-functions: check-swift-openapi-generator
	swift-openapi-generator generate \
	  --config Sources/Functions/openapi-generator-config.yaml \
	  --output-directory Sources/Functions/Generated \
	  smithy/output/openapi/FunctionsService.openapi.json

generate-swift-postgrest: check-swift-openapi-generator
	swift-openapi-generator generate \
	  --config Sources/PostgREST/openapi-generator-config.yaml \
	  --output-directory Sources/PostgREST/Generated \
	  smithy/output/openapi/DatabaseService.openapi.json

generate: sync-models generate-swift-storage generate-swift-functions generate-swift-postgrest

check-generate:
	$(MAKE) generate
	git diff --exit-code || (echo "Generated artifacts are out of date. Run 'make generate' and commit." && exit 1)
