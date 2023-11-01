PLATFORM_IOS = iOS Simulator,name=iPhone 14 Pro
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,name=Apple TV
PLATFORM_WATCHOS = watchOS Simulator,name=Apple Watch Series 8 (41mm)
EXAMPLE = Examples

test-library:
	for platform in "$(PLATFORM_IOS)" "$(PLATFORM_MACOS)" "$(PLATFORM_MAC_CATALYST)" "$(PLATFORM_TVOS)" "$(PLATFORM_WATCHOS)"; do \
		xcodebuild test \
			-workspace supabase-swift.xcworkspace \
			-scheme Supabase-Package \
			-destination platform="$$platform" || exit 1; \
	done;

build-example:
	xcodebuild build \
		-workspace supabase-swift.xcworkspace \
		-scheme "$(EXAMPLE)" \
		-destination platform="$(PLATFORM_IOS)" || exit 1;

format:
	@swiftformat .

.PHONY: test-library build-example format
