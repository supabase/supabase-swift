import Foundation
import XCTestDynamicOverlay

private let _version = "3.0.0-beta"  // {x-release-please-version}

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
      if ProcessInfo.processInfo.isiOSAppOnMac {
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

private func _swift6Version() -> String? {
  #if swift(>=7.0)
    return nil
  #elseif swift(>=6.9)
    return "6.9"
  #elseif swift(>=6.8)
    return "6.8"
  #elseif swift(>=6.7)
    return "6.7"
  #elseif swift(>=6.6)
    return "6.6"
  #elseif swift(>=6.5)
    return "6.5"
  #elseif swift(>=6.4)
    return "6.4"
  #elseif swift(>=6.3)
    return "6.3"
  #elseif swift(>=6.2)
    return "6.2"
  #elseif swift(>=6.1)
    return "6.1"
  #else
    return nil
  #endif
}

private func _swift7Version() -> String? {
  #if swift(>=8.0)
    return nil
  #elseif swift(>=7.9)
    return "7.9"
  #elseif swift(>=7.8)
    return "7.8"
  #elseif swift(>=7.7)
    return "7.7"
  #elseif swift(>=7.6)
    return "7.6"
  #elseif swift(>=7.5)
    return "7.5"
  #elseif swift(>=7.4)
    return "7.4"
  #elseif swift(>=7.3)
    return "7.3"
  #elseif swift(>=7.2)
    return "7.2"
  #elseif swift(>=7.1)
    return "7.1"
  #elseif swift(>=7.0)
    return "7.0"
  #else
    return nil
  #endif
}

private let _runtimeVersion: String? = _swift6Version() ?? _swift7Version()

#if DEBUG
  package let runtimeVersion: String? = isTesting ? "0.0.0" : _runtimeVersion
#else
  package let runtimeVersion = _runtimeVersion
#endif
