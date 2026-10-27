import ConcurrencyExtras
public import Foundation

/// A type that can persist, retrieve, and remove Auth session data on the local device.
///
/// Implement this protocol to provide a custom storage back-end for ``AuthClient``.
/// The default implementation uses the Keychain on Apple platforms. Other platforms default to
/// storage in memory, which loses the session when the process ends.
///
/// ## Topics
///
/// ### Implementing storage
/// - ``store(key:value:)``
/// - ``retrieve(key:)``
/// - ``remove(key:)``
public protocol AuthLocalStorage: Sendable {
  /// Persists `value` under `key`, replacing any existing value.
  ///
  /// - Parameters:
  ///   - key: The storage key.
  ///   - value: The raw bytes to persist.
  /// - Throws: An error if the write fails.
  func store(key: String, value: Data) throws

  /// Returns the value previously stored under `key`, or `nil` if none exists.
  ///
  /// - Parameter key: The storage key.
  /// - Returns: The stored bytes, or `nil` if the key is absent.
  /// - Throws: An error if the read fails.
  func retrieve(key: String) throws -> Data?

  /// Deletes the value stored under `key`, if any.
  ///
  /// - Parameter key: The storage key to delete.
  /// - Throws: An error if the delete fails.
  func remove(key: String) throws
}

extension AuthClient.Configuration {
  /// The platform-appropriate default local storage implementation.
  ///
  /// On Apple platforms this is a ``KeychainLocalStorage`` instance. Other platforms have no
  /// Keychain, so the default keeps values in memory and loses the session when the process ends.
  /// Pass your own ``AuthLocalStorage`` to persist the session.
  #if canImport(Security)
    public static let defaultLocalStorage: any AuthLocalStorage = KeychainLocalStorage()
  #else
    public static let defaultLocalStorage: any AuthLocalStorage = EphemeralLocalStorage()
  #endif
}

/// An ``AuthLocalStorage`` that keeps values in memory only.
struct EphemeralLocalStorage: AuthLocalStorage {
  private let values = LockIsolated<[String: Data]>([:])

  func store(key: String, value: Data) throws {
    values.withValue { $0[key] = value }
  }

  func retrieve(key: String) throws -> Data? {
    values.value[key]
  }

  func remove(key: String) throws {
    values.withValue { $0[key] = nil }
  }
}
