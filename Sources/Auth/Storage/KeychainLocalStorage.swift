#if !os(Windows) && !os(Linux) && !os(Android)
  public import Foundation

  /// The Keychain service ``KeychainLocalStorage`` stores its items under by default.
  ///
  /// Fixed since v2 so that sessions are read in place across SDK versions and shared across
  /// every target of an app that passes the same access group.
  let defaultKeychainService = "supabase.gotrue.swift"

  /// ``AuthLocalStorage`` implementation using Keychain. This is the default local storage used by the library.
  public struct KeychainLocalStorage: AuthLocalStorage {
    let keychain: any KeychainProtocol
    let legacyKeychains: [any KeychainProtocol]

    /// Creates a Keychain-backed storage instance using the SDK's default service.
    ///
    /// Items are stored under the fixed service `"supabase.gotrue.swift"`. The service is the
    /// same in every target and every SDK version, so sessions written by earlier versions are
    /// read in place, and an app and its extensions that pass the same access group share one
    /// session. Isolation between unrelated apps comes from the Keychain access group, not from
    /// the service name.
    ///
    /// - Parameters:
    ///   - accessGroup: An optional Keychain access group. Pass the same group from every target
    ///     that should see the same session: an app and its widget, share extension, or Watch
    ///     app, or several apps in one app group. `nil` scopes items to the app's own default
    ///     access group.
    ///   - useDataProtectionKeychain: Targets the macOS data-protection Keychain instead of the
    ///     legacy file-based one. This removes the macOS consent prompt, but requires the app to
    ///     be signed with entitlements authorized by a provisioning profile — otherwise Keychain
    ///     operations fail with `errSecMissingEntitlement` (-34018). Items do not move between
    ///     the two Keychains on their own, so a session written to the file-based one is
    ///     migrated on first read. Has no effect on platforms other than macOS. Defaults to
    ///     `false`.
    public init(accessGroup: String? = nil, useDataProtectionKeychain: Bool = false) {
      keychain = Keychain(
        service: defaultKeychainService,
        accessGroup: accessGroup,
        useDataProtectionKeychain: useDataProtectionKeychain
      )
      legacyKeychains =
        useDataProtectionKeychain
        ? [Keychain(service: defaultKeychainService, accessGroup: accessGroup)]
        : []
    }

    /// Creates a Keychain-backed storage instance with an explicit service.
    ///
    /// No other location is probed: the given service is used exactly as provided.
    ///
    /// - Parameters:
    ///   - service: The Keychain service name used to namespace stored items. Pass `nil` to omit
    ///     the attribute entirely.
    ///   - accessGroup: An optional Keychain access group. Every target that should see the same
    ///     session must pass the same `service` and the same `accessGroup`; the group alone does
    ///     not make items with different services match.
    ///   - useDataProtectionKeychain: See ``init(accessGroup:useDataProtectionKeychain:)``.
    public init(
      service: String?,
      accessGroup: String? = nil,
      useDataProtectionKeychain: Bool = false
    ) {
      keychain = Keychain(
        service: service,
        accessGroup: accessGroup,
        useDataProtectionKeychain: useDataProtectionKeychain
      )
      legacyKeychains = []
    }

    init(keychain: any KeychainProtocol, legacyKeychains: [any KeychainProtocol]) {
      self.keychain = keychain
      self.legacyKeychains = legacyKeychains
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
    /// If the item is absent but exists in a legacy location (the macOS file-based Keychain,
    /// once the data-protection one is in use), it is moved to the current location and returned.
    ///
    /// - Parameter key: The Keychain item key.
    /// - Returns: The stored bytes, or `nil` if the item does not exist.
    /// - Throws: A Keychain error if reading the current location fails, or if probing a legacy
    ///   location fails. A failure to write the migrated value is not thrown — the value that was
    ///   read is returned and the migration is retried on the next read.
    public func retrieve(key: String) throws -> Data? {
      if let data = try keychain.data(forKey: key) {
        return data
      }

      for legacy in legacyKeychains {
        // An absent legacy item reads as nil, so anything thrown here is a genuine failure —
        // a locked Keychain, a denied ACL prompt — and must not be reported as "no session".
        guard let data = try legacy.data(forKey: key) else { continue }

        do {
          try keychain.set(data, forKey: key)
          // Only drop the legacy copy once the new one has landed.
          try? legacy.deleteItem(forKey: key)
        } catch {
          // Leave the legacy copy in place; the next read retries the migration.
        }

        return data
      }

      return nil
    }

    /// Removes the Keychain item for `key`, including any left in a legacy location.
    ///
    /// - Parameter key: The Keychain item key to delete.
    /// - Throws: A Keychain error if deleting from the current location fails. Legacy-location
    ///   delete failures are ignored, with every location attempted regardless.
    public func remove(key: String) throws {
      var primaryError: (any Error)?
      do {
        try keychain.deleteItem(forKey: key)
      } catch {
        primaryError = error
      }

      for legacy in legacyKeychains {
        try? legacy.deleteItem(forKey: key)
      }

      if let primaryError {
        throw primaryError
      }
    }
  }
#endif
