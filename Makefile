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

# Run RealtimeV3 integration tests against a live local Supabase instance.
# Starts the dedicated realtimev3 project, resets the DB (applies migrations + seed),
# then runs the integration suite. The instance is intentionally left running after
# the first invocation so subsequent runs skip the slow start step.
# To stop: cd Tests/RealtimeV3IntegrationTests/supabase && supabase stop
test-realtime-v3-integration:
	cd Tests/RealtimeV3IntegrationTests/supabase && supabase start && supabase db reset --local
	swift test --filter RealtimeV3IntegrationTests

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

.PHONY: build-for-library-evolution format warm-simulator xcodebuild test-docs test-integration test-realtime-v3-integration

.PHONY: coverage
coverage:
	@DERIVED_DATA_PATH=$(DERIVED_DATA_PATH) ./scripts/generate-coverage.sh

define udid_for
$(shell xcrun simctl list --json devices available '$(1)' | jq -r '[.devices|to_entries|sort_by(.key)|reverse|.[].value|select(length > 0)|.[0]][0].udid')
endef
