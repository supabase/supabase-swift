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
    ///     data-protection Keychain.
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
      self.init(
        keychain: Keychain(
          service: service,
          accessGroup: accessGroup,
          accessibility: accessibility,
          synchronizable: synchronizable,
          useDataProtectionKeychain: useDataProtectionKeychain
        )
      )
    }

    init(keychain: any KeychainProtocol) {
      self.keychain = keychain
    }

    /// Returns the bytes stored in the Keychain under `key`, or `nil` when no item exists.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error.
    @concurrent
    public func load(key: String) async throws -> Data? {
      try mappingKeychainErrors { try keychain.data(forKey: key) }
    }

    /// Stores `data` in the Keychain under `key`. An existing item is updated in place.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error.
    @concurrent
    public func save(_ data: Data, key: String) async throws {
      try mappingKeychainErrors { try keychain.set(data, forKey: key) }
    }

    /// Removes the Keychain item stored under `key`. Removing a key with no item succeeds.
    ///
    /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/storageUnavailable`` or
    ///   ``AuthError/Kind-swift.struct/storageMisconfigured``, or the Keychain error.
    @concurrent
    public func remove(key: String) async throws {
      try mappingKeychainErrors { try keychain.deleteItem(forKey: key) }
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
