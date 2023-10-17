PLATFORM_IOS = iOS Simulator,name=iPhone 14 Pro Max

test-library:
	xcodebuild test \
		-workspace supabase-swift.xcworkspace \
		-scheme Supabase \
		-destination platform="$(PLATFORM_IOS)" || exit 1;

build-example:
	xcodebuild build \
		-workspace supabase-swift.xcworkspace \
		-scheme Examples \
		-destination platform="$(PLATFORM_IOS)" || exit 1;

format:
	@swift format -i -r .
