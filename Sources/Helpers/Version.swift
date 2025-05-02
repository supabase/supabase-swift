import XCTestDynamicOverlay

private let _version = "2.27.0"  // {x-release-please-version}

#if DEBUG
  package let version = isTesting ? "0.0.0" : _version
#else
  package let version = _version
#endif
