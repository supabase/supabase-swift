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
final class KeychainLocalStorage: AuthLocalStorage {
  private var keychain = [String: Data]()

  init(service: String, accessGroup: String?) {

  }

  func store(key: String, value: Data) throws {
    keychain[key] = value
  }

  func retrieve(key: String) throws -> Data? {
    keychain[key]
  }

  func remove(key: String) throws {
    keychain.removeValue(forKey: key)
  }
}
#endif
