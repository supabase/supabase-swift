CONFIG = debug
PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iOS 17.5,iPhone \d\+ Pro [^M])
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,tvOS 17.5,TV)
PLATFORM_VISIONOS = visionOS Simulator,id=$(call udid_for,visionOS 1.2,Vision)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,watchOS 10.5,Watch)

SCHEME ?= Supabase
PLATFORM ?= $(PLATFORM_IOS)

export SECRETS
define SECRETS
enum DotEnv {
  static let SUPABASE_URL = "$(SUPABASE_URL)"
  static let SUPABASE_ANON_KEY = "$(SUPABASE_ANON_KEY)"
  static let SUPABASE_SERVICE_ROLE_KEY = "$(SUPABASE_SERVICE_ROLE_KEY)"
}
endef

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
			-destination generic/platform="$$platform" | xcpretty || exit 1; \
	done

test-library: dot-env
	for platform in "$(PLATFORM_IOS)" "$(PLATFORM_MACOS)"; do \
		xcodebuild test \
			-skipMacroValidation \
			-configuration "$(CONFIG)" \
			-workspace Supabase.xcworkspace \
			-scheme "$(SCHEME)" \
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

build-examples:
	for scheme in Examples UserManagement SlackClone; do \
		set -o pipefail && \
			xcodebuild build \
				-skipMacroValidation \
				-workspace Supabase.xcworkspace \
				-scheme "$$scheme" \
				-destination platform="$(PLATFORM_IOS)" | xcpretty; \
	done

format:
	@swiftformat .

.PHONY: test-library test-linux build-example format

define udid_for
$(shell xcrun simctl list devices available '$(1)' | grep '$(2)' | sort -r | head -1 | awk -F '[()]' '{ print $$(NF-3) }')
endef