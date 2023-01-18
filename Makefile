PLATFORM_IOS = iOS Simulator,name=iPhone 14 Pro Max

build-example:
	xcodebuild build \
		-workspace supabase-swift.xcworkspace \
		-scheme Examples \
		-destination platform="$(PLATFORM_IOS)" || exit 1;

format:
	@swiftformat .
