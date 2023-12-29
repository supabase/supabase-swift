#if !os(Windows) && !os(Linux)
import Foundation
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
#endif
