PLATFORM_IOS = iOS Simulator,name=iPhone 15 Pro
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,name=Apple TV
PLATFORM_WATCHOS = watchOS Simulator,name=Apple Watch Series 9 (41mm)

SCHEME ?= Supabase
PLATFORM ?= iOS Simulator,name=iPhone 15 Pro

export SECRETS
define SECRETS
enum DotEnv {
  static let SUPABASE_URL = "$(SUPABASE_URL)"
  static let SUPABASE_ANON_KEY = "$(SUPABASE_ANON_KEY)"
}
endef

load-env:
	@. ./scripts/load_env.sh

dot-env:
	@echo "$$SECRETS" > Tests/IntegrationTests/DotEnv.swift

test-all: dot-env
	set -o pipefail && \
			xcodebuild test \
				-skipMacroValidation \
				-workspace supabase-swift.xcworkspace \
				-scheme "$(SCHEME)" \
				-testPlan AllTests \
				-destination platform="$(PLATFORM)" | xcpretty

test-library: dot-env
	set -o pipefail && \
			xcodebuild test \
				-skipMacroValidation \
				-workspace supabase-swift.xcworkspace \
				-scheme "$(SCHEME)" \
				-derivedDataPath /tmp/derived-data \
				-destination platform="$(PLATFORM)" | xcpretty

test-integration: dot-env
	set -o pipefail && \
		xcodebuild test \
			-skipMacroValidation \
			-workspace supabase-swift.xcworkspace \
			-scheme Supabase \
			-testPlan IntegrationTests \
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
				-workspace supabase-swift.xcworkspace \
				-scheme "$$scheme" \
				-destination platform="$(PLATFORM_IOS)" | xcpretty; \
	done

format:
	@swiftformat .

.PHONY: test-library test-linux build-example format
