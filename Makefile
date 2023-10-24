PLATFORM ?= iOS Simulator,name=iPhone 15 Pro

test-library:
	xcodebuild test \
		-workspace supabase-swift.xcworkspace \
		-scheme Supabase-Package \
		-destination platform="$(PLATFORM)" || exit 1;

build-example:
	for example in "Examples" "ProductSample"; do \
		xcodebuild build \
			-workspace supabase-swift.xcworkspace \
			-scheme "$$example" \
			-destination platform="$(PLATFORM)" || exit 1; \
	done;

format:
	@swift format -i -r .

.PHONY: test-library build-example format