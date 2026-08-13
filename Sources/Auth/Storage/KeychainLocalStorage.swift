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
    let keychain: any KeychainProtocol
    let legacyKeychains: [any KeychainProtocol]

    /// Creates a Keychain-backed storage instance scoped to the host application.
    ///
    /// The Keychain service defaults to the host app's bundle identifier, so items are namespaced
    /// per application. Sessions written by earlier SDK versions, which used a fixed
    /// `"supabase.gotrue.swift"` service, migrate automatically on first read.
    ///
    /// - Parameters:
    ///   - accessGroup: An optional Keychain access group for sharing items between apps.
    ///   - useDataProtectionKeychain: Targets the macOS data-protection Keychain instead of the
    ///     legacy file-based one. This removes the macOS consent prompt, but requires the app to
    ///     be signed with entitlements authorized by a provisioning profile — otherwise Keychain
    ///     operations fail with `errSecMissingEntitlement` (-34018). Has no effect on platforms
    ///     other than macOS. Defaults to `false`.
    public init(accessGroup: String? = nil, useDataProtectionKeychain: Bool = false) {
      let primary = Self.primaryConfiguration(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        accessGroup: accessGroup,
        useDataProtectionKeychain: useDataProtectionKeychain
      )

      keychain = Keychain(primary)
      legacyKeychains = Self.legacyConfigurations(primary: primary).map { Keychain($0) }
    }

    /// Creates a Keychain-backed storage instance with an explicit service.
    ///
    /// No migration is performed: the given service is used exactly as provided.
    ///
    /// - Parameters:
    ///   - service: The Keychain service name used to namespace stored items. Pass `nil` to omit
    ///     the attribute entirely.
    ///   - accessGroup: An optional Keychain access group for sharing items between apps.
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
    /// If the item is absent but exists in a location used by an earlier SDK version, it is moved
    /// to the current location and returned.
    ///
    /// - Parameter key: The Keychain item key.
    /// - Returns: The stored bytes, or `nil` if the item does not exist.
    /// - Throws: A Keychain error if the read from the current location fails. Failures while
    ///   probing or migrating from a legacy location are ignored — a value that was read is
    ///   always returned.
    public func retrieve(key: String) throws -> Data? {
      if let data = try keychain.data(forKey: key) {
        return data
      }

      for legacy in legacyKeychains {
        // A failing probe must not break a fresh install, so failures are ignored here.
        guard let data = try? legacy.data(forKey: key) else { continue }

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
