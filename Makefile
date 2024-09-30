CONFIG = debug
PLATFORM = iOS
PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS,Watch)

export SECRETS
define SECRETS
enum DotEnv {
  static let SUPABASE_URL = "$(SUPABASE_URL)"
  static let SUPABASE_ANON_KEY = "$(SUPABASE_ANON_KEY)"
  static let SUPABASE_SERVICE_ROLE_KEY = "$(SUPABASE_SERVICE_ROLE_KEY)"
}
endef

default: test-all

test-all:
	$(MAKE) CONFIG=debug test-library
	$(MAKE) CONFIG=release test-library

xcodebuild:
	if test "$(PLATFORM)" = "iOS"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_IOS)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		elif test "$(PLATFORM)" = "macOS"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_MACOS)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		elif test "$(PLATFORM)" = "tvOS"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_TVOS)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		elif test "$(PLATFORM)" = "watchOS"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_WATCHOS)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		elif test "$(PLATFORM)" = "visionOS"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_VISIONOS)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		elif test "$(PLATFORM)" = "macCatalyst"; \
		then xcodebuild $(COMMAND) \
			-skipMacroValidation \
			-configuration $(CONFIG) \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-destination platform="$(PLATFORM_MAC_CATALYST)" \
			-derivedDataPath ~/.derivedData/$(CONFIG) | xcpretty; \
		else exit 1; \
		fi;	

load-env:
	@. ./scripts/load_env.sh

dot-env:
	@echo "$$SECRETS" > Tests/IntegrationTests/DotEnv.swift


build-all-platforms: 
	for platform in "iOS" "macOS" "macOS,variant=Mac Catalyst" "tvOS" "visionOS" "watchOS"; do \
		xcodebuild \
			-skipMacroValidation \
			-configuration "$(CONFIG)" \
			-workspace Supabase.xcworkspace \
			-scheme "$(SCHEME)" \
			-testPlan AllTests \
			-destination platform="$$platform" | xcpretty || exit 1; \
	done

test-auth:
	$(MAKE) SCHEME=Auth test-library

test-functions:
	$(MAKE) SCHEME=Functions test-library

test-postgrest:
	$(MAKE) SCHEME=PostgREST test-library

test-realtime:
	$(MAKE) SCHEME=Realtime test-library

test-storage:
	$(MAKE) SCHEME=Storage test-library

test-integration: dot-env
	set -o pipefail && \
		xcodebuild test \
			-skipMacroValidation \
			-workspace Supabase.xcworkspace \
			-scheme Supabase \
			-testPlan Integration \
			-destination platform="$(PLATFORM_IOS)" | xcpretty


test-linux:
	docker build -t supabase-swift .
	docker run supabase-swift

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

build-example:
	xcodebuild build \
		-skipMacroValidation \
		-workspace Supabase.xcworkspace \
		-scheme "$(SCHEME)" \
		-destination platform="$(PLATFORM_IOS)" \
		-derivedDataPath ~/.derivedData | xcpretty;

format:
	@swiftformat .

.PHONY: test-library test-linux build-example format

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef