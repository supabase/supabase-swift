PLATFORM_IOS = iOS Simulator,name=iPhone 15 Pro
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,name=Apple TV
PLATFORM_WATCHOS = watchOS Simulator,name=Apple Watch Series 9 (41mm)
EXAMPLE = Examples

test-library:
	for platform in "$(PLATFORM_IOS)" "$(PLATFORM_MACOS)" "$(PLATFORM_MAC_CATALYST)" "$(PLATFORM_TVOS)" "$(PLATFORM_WATCHOS)"; do \
		xcodebuild test \
			-workspace supabase-swift.xcworkspace \
			-scheme Supabase \
			-destination platform="$$platform" || exit 1; \
	done;

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
	for scheme in Examples UserManagement; do \
		xcodebuild build \
			-workspace supabase-swift.xcworkspace \
			-scheme "$$scheme" \
			-destination platform="$(PLATFORM_IOS)" || exit 1; \
	done

format:
	@swiftformat .

.PHONY: test-library build-example format
