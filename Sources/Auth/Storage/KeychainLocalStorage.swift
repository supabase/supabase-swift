#if !os(Windows) && !os(Linux)
import Foundation
@preconcurrency import KeychainAccess

public struct KeychainLocalStorage: AuthLocalStorage {
  private let keychain: Keychain

  public init(service: String, accessGroup: String?) {
    if let accessGroup {
      keychain = Keychain(service: service, accessGroup: accessGroup)
    } else {
      keychain = Keychain(service: service)
    }
  }

  public func store(key: String, value: Data) throws {
    try keychain.set(value, key: key)
  }

  public func retrieve(key: String) throws -> Data? {
    try keychain.getData(key)
  }

  public func remove(key: String) throws {
    try keychain.remove(key)
  }
}
#endif
