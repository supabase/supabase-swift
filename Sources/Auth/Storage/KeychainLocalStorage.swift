#if !os(Windows) && !os(Linux) && !os(Android)
  import Foundation

  /// ``AuthLocalStorage`` implementation using Keychain. This is the default local storage used by the library.
  public struct KeychainLocalStorage: AuthLocalStorage {
    private let keychain: Keychain

    /// Creates a Keychain-backed storage instance.
    ///
    /// - Parameters:
    ///   - service: The Keychain service name used to namespace stored items.
    ///     Defaults to `"supabase.gotrue.swift"`.
    ///   - accessGroup: An optional Keychain access group for sharing items between apps.
    public init(service: String? = "supabase.gotrue.swift", accessGroup: String? = nil) {
      keychain = Keychain(service: service, accessGroup: accessGroup)
    }

    /// Stores `value` in the Keychain under `key`.
    ///
    /// - Parameters:
    ///   - key: The Keychain item key.
    ///   - value: The raw bytes to store.
    /// - Throws: A Keychain error if the write fails.
    public func store(key: String, value: Data) throws {
      try keychain.set(value, forKey: key)
    }

    /// Returns the data stored in the Keychain for `key`, or `nil` if not present.
    ///
    /// - Parameter key: The Keychain item key.
    /// - Returns: The stored bytes, or `nil` if the item does not exist.
    /// - Throws: A Keychain error if the read fails.
    public func retrieve(key: String) throws -> Data? {
      try keychain.data(forKey: key)
    }

    /// Removes the Keychain item for `key`.
    ///
    /// - Parameter key: The Keychain item key to delete.
    /// - Throws: A Keychain error if the delete fails.
    public func remove(key: String) throws {
      try keychain.deleteItem(forKey: key)
    }
  }
#endif
