import Foundation
@preconcurrency import KeychainAccess

public protocol GoTrueLocalStorage: Sendable {
  func store(key: String, value: Data) throws
  func retrieve(key: String) throws -> Data?
  func remove(key: String) throws
}

struct KeychainLocalStorage: GoTrueLocalStorage {
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
