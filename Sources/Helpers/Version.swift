import Foundation
import XCTestDynamicOverlay

private let _version = "2.26.0"  // {x-release-please-version}

#if DEBUG
  package let version = isTesting ? "0.0.0" : _version
#else
  package let version = _version
#endif

private let _platform: String? = {
  #if os(macOS)
    return "macOS"
  #elseif os(iOS)
    return "iOS"
  #elseif os(tvOS)
    return "tvOS"
  #elseif os(watchOS)
    return "watchOS"
  #elseif os(Android)
    return "Android"
  #elseif os(Linux)
    return "Linux"
  #elseif os(Windows)
    return "Windows"
  #else
    return nil
  #endif
}()

private let _platformVersion: String? = {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(Windows)
    ProcessInfo.processInfo.operatingSystemVersionString
  #elseif os(Linux) || os(Android)
    if let version = try? String(contentsOfFile: "/proc/version") {
      version.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      nil
    }
  #else
    nil
  #endif
}()

#if DEBUG
  package let platform = isTesting ? "macOS" : _platform
#else
  package let platform = _platform
#endif

#if DEBUG
  package let platformVersion = isTesting ? "0.0.0" : _platformVersion
#else
  package let platformVersion = _platformVersion
#endif
