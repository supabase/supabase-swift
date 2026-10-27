import Foundation

/// Which values a storage reads and writes, so that only clients over the same values share a
/// ``SessionStore``.
///
/// Two storages have one identity only when a write through one is visible through the other: the
/// same class instance, copies of one in-memory storage, or Keychain storages that address the
/// same items. A storage whose values cannot be told apart, such as a custom struct, has no
/// identity.
enum StorageIdentity: Hashable {
  case object(ObjectIdentifier)
  case keychain(
    service: String?, accessGroup: String?, synchronizable: Bool, useDataProtectionKeychain: Bool)

  init?(of storage: Any) {
    switch storage {
    case let adapter as AuthLocalStorageAdapter:
      self.init(of: adapter.localStorage)
    case let storage as InMemoryAuthStorage:
      self = .object(ObjectIdentifier(storage.values))
    case let storage as EphemeralLocalStorage:
      self = .object(ObjectIdentifier(storage.values))
    #if canImport(Security)
      case let storage as KeychainLocalStorage:
        self.init(of: storage.keychain)
      case let storage as KeychainStorage:
        self.init(of: storage.keychain)
      case let keychain as Keychain:
        self = .keychain(
          service: keychain.service,
          accessGroup: keychain.accessGroup,
          synchronizable: keychain.synchronizable,
          useDataProtectionKeychain: keychain.useDataProtectionKeychain
        )
    #endif
    default:
      guard type(of: storage) is AnyClass else { return nil }
      self = .object(ObjectIdentifier(storage as AnyObject))
    }
  }
}
