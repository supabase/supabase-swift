#if canImport(Security)
  public import Foundation
  import Security

  /// An ``AuthStorage`` that stores each value as a generic-password item in the Keychain.
  ///
  /// The defaults keep a session on this device and readable by background refresh:
  ///
  /// - Items use ``Accessibility-swift.enum/afterFirstUnlockThisDeviceOnly``, so they are
  ///   readable after the first unlock since boot and never move to another device through a
  ///   backup or iCloud Keychain.
  /// - On macOS, items go to the data-protection Keychain. That Keychain needs an app signed with
  ///   the keychain-access-groups entitlement. Unsigned tools and test bundles get
  ///   ``AuthError/Kind-swift.struct/storageMisconfigured``; use ``InMemoryAuthStorage`` there.
  ///
  /// ## Upgrading from an earlier SDK version
  ///
  /// A session an earlier version wrote is found in place: the default service is unchanged.
  /// The first write moves the item to the new accessibility with an in-place update, so the item
  /// is never missing. On macOS, an item in the legacy file-based Keychain moves to the
  /// data-protection Keychain on the first load.
  ///
  /// ## Choosing other settings
  ///
  /// - To keep the session when a backup is restored to a new device, pass
  ///   `accessibility: .afterFirstUnlock`.
  /// - For a command-line tool that cannot be signed with the keychain-access-groups
  ///   entitlement, pass `useDataProtectionKeychain: false`.
  /// - To ask for Face ID or Touch ID before the app uses the session, gate your app's UI with
  ///   `LAContext.evaluatePolicy(_:localizedReason:)`. The storage does not gate Keychain reads
  ///   on biometrics, because background refresh must read the session without the user.
  ///
  /// ## Signing out after a reinstall
  ///
  /// Keychain items survive when the user deletes the app, so a user who reinstalls it is still
  /// signed in. To sign out instead, keep a first-launch flag in your app's `UserDefaults`, which
  /// the system deletes with the app, and sign out when the flag is missing:
  ///
  /// ```swift
  /// if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
  ///   do {
  ///     try await supabase.auth.signOut()
  ///     UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
  ///   } catch {
  ///     // Keep the flag unset, so the next launch tries again.
  ///   }
  /// }
  /// ```
  ///
  /// Run it in the main app only. An app extension has its own `UserDefaults`, so the check
  /// there would sign out the session the app shares with it. Shipping the check in an update
  /// signs out every existing user once, because none of them has the flag yet.
  ///
  /// ## Errors
  ///
  /// Every operation throws ``AuthError`` with kind
  /// ``AuthError/Kind-swift.struct/storageUnavailable`` when the item is not accessible yet, for
  /// example before the first unlock. That is not "signed out": try again later. It throws kind
  /// ``AuthError/Kind-swift.struct/storageMisconfigured`` when the app lacks the Keychain
  /// entitlement (`errSecMissingEntitlement`). Other Keychain failures propagate unchanged.
  public struct KeychainStorage: AuthStorage {
    /// When the Keychain lets the app read an item.
    ///
    /// Each case maps to one `kSecAttrAccessible` value. Cases that end in `ThisDeviceOnly` keep
    /// the item out of backups restored to another device and out of iCloud Keychain.
    public enum Accessibility: Sendable, Hashable {
      /// Readable while the device is unlocked (`kSecAttrAccessibleWhenUnlocked`). Background
      /// refresh fails while the device is locked.
      case whenUnlocked
      /// Readable while the device is unlocked, and never leaves this device
      /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
      case whenUnlockedThisDeviceOnly
      /// Readable after the first unlock since boot (`kSecAttrAccessibleAfterFirstUnlock`).
      case afterFirstUnlock
      /// Readable after the first unlock since boot, and never leaves this device
      /// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). The default.
      case afterFirstUnlockThisDeviceOnly
      /// Readable while the device is unlocked and has a passcode, and never leaves this device
      /// (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`). Removing the passcode deletes
      /// the item.
      case whenPasscodeSetThisDeviceOnly
    }

    let keychain: any KeychainProtocol

    /// Locations probed when an item is missing from ``keychain``. Only the macOS file-based
    /// Keychain is one, and only while the data-protection Keychain is in use.
    let legacyKeychains: [any KeychainProtocol]

    /// Creates a Keychain-backed storage.
    ///
    /// - Parameters:
    ///   - service: The Keychain service the items are stored under. The default is the
    ///     service every earlier SDK version used, so a session written by an earlier version
    ///     is found after an upgrade.
    ///   - accessGroup: A Keychain access group, such as
    ///     `"$(AppIdentifierPrefix)com.example.shared"`. Pass the same group from every target
    ///     that should share the session: an app and its widget, share extension, or App Clip.
    ///     Each target needs the group in its entitlements. `nil` uses the app's default group.
    ///   - accessibility: When the Keychain lets the app read the items.
    ///   - synchronizable: Whether items sync to the user's other devices through iCloud
    ///     Keychain. Requires an `accessibility` that does not end in `ThisDeviceOnly`.
    ///   - useDataProtectionKeychain: On macOS, whether to use the data-protection Keychain
    ///     instead of the legacy file-based one. Pass `false` only for apps that cannot be
    ///     signed with the keychain-access-groups entitlement. Other platforms always use the
    ///     data-protection Keychain. Items do not move between the two Keychains on their own,
    ///     so with `true` a session that the file-based Keychain holds is moved on the first
    ///     load.
    ///
    /// - Precondition: `synchronizable` is `false`, or `accessibility` does not end in
    ///   `ThisDeviceOnly`.
    public init(
      service: String = "supabase.gotrue.swift",
      accessGroup: String? = nil,
      accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly,
      synchronizable: Bool = false,
      useDataProtectionKeychain: Bool = true
    ) {
      precondition(
        !synchronizable || !accessibility.isThisDeviceOnly,
        "KeychainStorage: a synchronizable item cannot use the \(accessibility) accessibility. "
          + "Pick one that does not end in ThisDeviceOnly, or set synchronizable to false."
      )
      #if os(macOS)
        let legacyKeychains: [any KeychainProtocol] =
          useDataProtectionKeychain
          ? [Keychain(service: service, accessGroup: accessGroup, accessibility: accessibility)]
          : []
      #else
        let legacyKeychains: [any KeychainProtocol] = []
      #endif
      self.init(
        keychain: Keychain(
          service: service,
          accessGroup: accessGroup,
          accessibility: accessibility,
          synchronizable: synchronizable,
          useDataProtectionKeychain: useDataProtectionKeychain
        ),
        legacyKeychains: legacyKeychains
      )
    }

    init(keychain: any KeychainProtocol, legacyKeychains: [any KeychainProtocol] = []) {
      self.keychain = keychain
      self.legacyKeychains = legacyKeychains
    }

    /// Returns the bytes stored in the Keychain under `key`, or `nil` when no item exists.
    ///
    /// If the item is absent but exists in a legacy location (the macOS file-based Keychain,
    /// once the data-protection one is in use), it is moved to the current location and returned.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error, if reading
    ///   the current location or probing a legacy location fails. A failed write of the moved
    ///   value does not throw. The read value is returned, and the next load retries the move.
    @concurrent
    public func load(key: String) async throws -> Data? {
      if let data = try mappingKeychainErrors({ try keychain.data(forKey: key) }) {
        return data
      }

      for legacy in legacyKeychains {
        guard let data = try mappingKeychainErrors({ try legacy.data(forKey: key) }) else {
          continue
        }

        do {
          try keychain.set(data, forKey: key)
          try? legacy.deleteItem(forKey: key)
        } catch {}

        return data
      }

      return nil
    }

    /// Stores `data` in the Keychain under `key`. An existing item is updated in place.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error.
    @concurrent
    public func save(_ data: Data, key: String) async throws {
      try mappingKeychainErrors { try keychain.set(data, forKey: key) }
    }

    /// Removes the Keychain item stored under `key`, including any left in a legacy location.
    /// Removing a key with no item succeeds.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error, if deleting
    ///   from the current or a legacy location fails. Every location is attempted regardless, and
    ///   the current location's error wins.
    @concurrent
    public func remove(key: String) async throws {
      var primaryError: (any Error)?
      var legacyError: (any Error)?
      do {
        try mappingKeychainErrors { try keychain.deleteItem(forKey: key) }
      } catch {
        primaryError = error
      }

      for legacy in legacyKeychains {
        do {
          try mappingKeychainErrors { try legacy.deleteItem(forKey: key) }
        } catch {
          legacyError = legacyError ?? error
        }
      }

      if let error = primaryError ?? legacyError {
        throw error
      }
    }
  }

  extension KeychainStorage.Accessibility {
    var isThisDeviceOnly: Bool {
      switch self {
      case .whenUnlocked, .afterFirstUnlock: false
      case .whenUnlockedThisDeviceOnly, .afterFirstUnlockThisDeviceOnly,
        .whenPasscodeSetThisDeviceOnly:
        true
      }
    }

    var secAttrValue: CFString {
      switch self {
      case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
      case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
      case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      case .whenPasscodeSetThisDeviceOnly: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
      }
    }
  }
#endif
