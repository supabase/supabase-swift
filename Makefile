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

SCHEME = Supabase

WORKSPACE = Supabase.xcworkspace

XCODEBUILD_ARGUMENT = test

XCODEBUILD_FLAGS = \
	-configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	-destination $(DESTINATION) \
	-scheme "$(SCHEME)" \
	-skipMacroValidation \
	-workspace $(WORKSPACE) \

XCODEBUILD_COMMAND = xcodebuild $(XCODEBUILD_ARGUMENT) $(XCODEBUILD_FLAGS)

ifneq ($(strip $(shell which xcbeautify)),)
	XCODEBUILD = set -o pipefail && $(XCODEBUILD_COMMAND) | xcbeautify --quiet
else
	XCODEBUILD = $(XCODEBUILD_COMMAND)
endif

TEST_RUNNER_CI = $(CI)

xcodebuild:
	$(XCODEBUILD)

test-integration:
	cd Tests/IntegrationTests && supabase start && supabase db reset
	swift test --filter IntegrationTests
	cd Tests/IntegrationTests && supabase stop

build-for-library-evolution:
	swift build \
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
	@swift format -i -r --ignore-unparsable-files .


test-linux:
	docker run \
		--rm \
		-v "$(PWD):$(PWD)" \
		-w "$(PWD)" \
		swift:5.10 \
		bash -c 'swift test -c $(CONFIG)'

build-linux:
	docker run \
		--rm \
		-v "$(PWD):$(PWD)" \
		-w "$(PWD)" \
		swift:5.9 \
		bash -c 'swift build -c $(CONFIG)'

.PHONY: build-for-library-evolution format xcodebuild test-docs test-integration

.PHONY: coverage
coverage:
	@DERIVED_DATA_PATH=$(DERIVED_DATA_PATH) ./scripts/generate-coverage.sh

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef