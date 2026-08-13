#if !os(Windows) && !os(Linux) && !os(Android)
  public import Foundation

  /// The Keychain service used by versions of the SDK before v3.
  let legacyKeychainService = "supabase.gotrue.swift"

  /// Identifies a single Keychain location.
  struct KeychainConfiguration: Equatable, Sendable {
    var service: String?
    var accessGroup: String?
    var useDataProtectionKeychain: Bool
  }

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

  extension KeychainLocalStorage {
    /// Resolves the Keychain location used when the caller accepts the default service.
    ///
    /// Falls back to ``legacyKeychainService`` when there is no bundle identifier, which is the
    /// case for command-line tools and some test bundles.
    static func primaryConfiguration(
      bundleIdentifier: String?,
      accessGroup: String?,
      useDataProtectionKeychain: Bool
    ) -> KeychainConfiguration {
      KeychainConfiguration(
        service: bundleIdentifier ?? legacyKeychainService,
        accessGroup: accessGroup,
        useDataProtectionKeychain: useDataProtectionKeychain
      )
    }

    /// The locations to probe, in order, when `primary` holds no value.
    ///
    /// Entries equal to `primary`, and duplicates, are removed.
    static func legacyConfigurations(
      primary: KeychainConfiguration
    ) -> [KeychainConfiguration] {
      var candidates: [KeychainConfiguration] = [
        KeychainConfiguration(
          service: legacyKeychainService,
          accessGroup: primary.accessGroup,
          useDataProtectionKeychain: false
        )
      ]

      if primary.useDataProtectionKeychain {
        // Items do not move between the two macOS Keychain implementations, so the previously
        // used file-based location has to be probed too.
        candidates.append(
          KeychainConfiguration(
            service: primary.service,
            accessGroup: primary.accessGroup,
            useDataProtectionKeychain: false
          )
        )
      }

      var result: [KeychainConfiguration] = []
      for candidate in candidates where candidate != primary && !result.contains(candidate) {
        result.append(candidate)
      }
      return result
    }
  }
#endif
