public import Foundation

/// A type that persists Auth data, such as the session and PKCE code verifiers, as raw bytes
/// under string keys.
///
/// The SDK ships three implementations:
///
/// - ``KeychainStorage`` on Apple platforms.
/// - ``FileAuthStorage`` for platforms without a Keychain, such as Linux and Android.
/// - ``InMemoryAuthStorage`` for tests and for apps that must not persist a session.
///
/// Implement this protocol to store Auth data somewhere else, for example in the Android
/// Keystore.
///
/// ## Throwing versus returning `nil`
///
/// ``load(key:)`` returns `nil` only when nothing is stored under the key. When the storage
/// cannot be read, throw. The client treats `nil` as "signed out", so returning `nil` for a
/// failed read signs the user out, for example when the device is locked.
///
/// ## Topics
///
/// ### Implementing storage
/// - ``load(key:)``
/// - ``save(_:key:)``
/// - ``remove(key:)``
public protocol AuthStorage: Sendable {
  /// Returns the bytes stored under `key`, or `nil` when nothing is stored under it.
  ///
  /// - Parameter key: The storage key.
  /// - Returns: The stored bytes, or `nil` when the key is absent.
  /// - Throws: An error when the storage cannot be read. Do not return `nil` instead.
  func load(key: String) async throws -> Data?

  /// Stores `data` under `key`, replacing any value already stored under it.
  ///
  /// - Parameters:
  ///   - data: The bytes to store.
  ///   - key: The storage key.
  /// - Throws: An error when the write fails.
  func save(_ data: Data, key: String) async throws

  /// Removes the value stored under `key`. Removing a key that is absent succeeds.
  ///
  /// - Parameter key: The storage key.
  /// - Throws: An error when the delete fails.
  func remove(key: String) async throws
}
