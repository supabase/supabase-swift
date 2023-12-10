import Foundation

public protocol AuthLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

#if !os(Windows) && !os(Linux)
@preconcurrency import KeychainAccess

struct KeychainLocalStorage: AuthLocalStorage {
  private let keychain: Keychain

  init(service: String, accessGroup: String?) {
    if let accessGroup {
      keychain = Keychain(service: service, accessGroup: accessGroup)
    } else {
      keychain = Keychain(service: service)
    }
  }

  func store(key: String, value: Data) throws {
    try keychain.set(value, key: key)
  }

  func retrieve(key: String) throws -> Data? {
    try keychain.getData(key)
  }

  func remove(key: String) throws {
    try keychain.remove(key)
  }
}
#else
// Secure storage in Linux seems to be quite different than say macOS and Windows
// The keyctl API set exists, but it doesn't persist across reboots like the
// keychain on macOS and the password vault (wincred.h) on Windows does. So this
// provides a bit of a challenge of how to implement this on Linux.
//
// What is likely needed here are specific implementations that use:
// - keyctl on Linux (https://www.kernel.org/doc/html/v6.0/security/keys/core.html)
// - DPAPI on Windows (https://learn.microsoft.com/en-us/windows/win32/api/dpapi/)
// Perhaps this is a patch on KeychainAccess to make this easier for others
final class KeychainLocalStorage: AuthLocalStorage {
  private let defaults: UserDefaults

  init(service: String, accessGroup: String?) {
    guard let defaults = UserDefaults(suiteName: service) else {
      fatalError("Unable to create defautls for service: \(service)")
    }

    self.defaults = defaults
  }

  func store(key: String, value: Data) throws {
    print("[WARN] YOU ARE YOU WRITING TO INSECURE LOCAL STORAGE")
    defaults.set(value, forKey: key)
  }

  func retrieve(key: String) throws -> Data? {
    print("[WARN] YOU ARE READING FROM INSECURE LOCAL STORAGE")
    return defaults.data(forKey: key)
  }

  func remove(key: String) throws {
    print("[WARN] YOU ARE REMOVING A KEY FROM INSECURE LOCAL STORAGE")
    defaults.removeObject(forKey: key)
  }
}
#endif
