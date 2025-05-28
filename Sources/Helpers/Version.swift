import Foundation
import XCTestDynamicOverlay

private let _version = "2.29.1"  // {x-release-please-version}

#if DEBUG
  package let version = isTesting ? "0.0.0" : _version
#else
  package let version = _version
#endif

private let _platform: String? = {
  #if os(macOS)
    return "macOS"
  #elseif os(visionOS)
    return "visionOS"
  #elseif os(iOS)
    #if targetEnvironment(macCatalyst)
      return "macCatalyst"
    #else
      if #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
        return "iOSAppOnMac"
      }
      return "iOS"
    #endif
  #elseif os(watchOS)
    return "watchOS"
  #elseif os(tvOS)
    return "tvOS"
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
    let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    let minorVersion = ProcessInfo.processInfo.operatingSystemVersion.minorVersion
    let patchVersion = ProcessInfo.processInfo.operatingSystemVersion.patchVersion
    return "\(majorVersion).\(minorVersion).\(patchVersion)"
  #elseif os(Linux) || os(Android)
    if let version = try? String(contentsOfFile: "/proc/version") {
      return version.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      return nil
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
