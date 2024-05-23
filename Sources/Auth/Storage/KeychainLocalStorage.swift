#if !os(Windows) && !os(Linux)
  import Foundation

  public struct KeychainLocalStorage: AuthLocalStorage {
    private let keychain: Keychain

    public init(service: String, accessGroup: String?) {
      keychain = Keychain(service: service, accessGroup: accessGroup)
    }

    public func store(key: String, value: Data) throws {
      try keychain.set(value, forKey: key)
    }

    public func retrieve(key: String) throws -> Data? {
      try keychain.data(forKey: key)
    }

    public func remove(key: String) throws {
      try keychain.deleteItem(forKey: key)
    }
  }
#endif
