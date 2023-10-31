PLATFORM ?= iOS Simulator,name=iPhone 15 Pro
EXAMPLE ?= Examples

test-library:
	xcodebuild test \
		-workspace supabase-swift.xcworkspace \
		-scheme Supabase-Package \
		-destination platform="$(PLATFORM)" || exit 1;

build-example:
	xcodebuild build \
		-workspace supabase-swift.xcworkspace \
		-scheme "$(EXAMPLE)" \
		-destination platform="$(PLATFORM)" || exit 1;

format:
	@swiftformat .

.PHONY: test-library build-example format
