PLATFORM_IOS = iOS Simulator,id=$(call udid_for,iPhone,iOS-16)
PLATFORM_MACOS = macOS
PLATFORM_MAC_CATALYST = macOS,variant=Mac Catalyst
PLATFORM_TVOS = tvOS Simulator,id=$(call udid_for,TV,tvOS-16)
PLATFORM_WATCHOS = watchOS Simulator,id=$(call udid_for,Watch,watchOS-9)

test-library:
	for platform in "$(PLATFORM_IOS)" "$(PLATFORM_MACOS)" "$(PLATFORM_MAC_CATALYST)" "$(PLATFORM_TVOS)" "$(PLATFORM_WATCHOS)"; do \
		xcodebuild test \
			-workspace supabase-swift.xcworkspace \
			-scheme Supabase-Package \
			-destination platform="$$platform" || exit 1; \
	done;

build-example:
	for example in "ProductSample"; do \
		xcodebuild build \
			-workspace supabase-swift.xcworkspace \
			-scheme "$$example" \
			-destination platform="$(PLATFORM_IOS)" || exit 1; \
	done;

format:
	@swift format -i -r .

.PHONY: test-library build-example format

define udid_for
$(shell xcrun simctl list --json devices available $(1) | jq -r '.devices | to_entries | map(select(.value | add)) | sort_by(.key) | .[] | select(.key | contains("$(2)")) | .value | last.udid')
endef