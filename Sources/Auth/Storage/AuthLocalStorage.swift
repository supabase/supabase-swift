public import Foundation

/// A type that can persist, retrieve, and remove Auth session data on the local device.
///
/// Implement this protocol to provide a custom storage back-end for ``AuthClient``.
/// The default implementation uses the Keychain on Apple platforms and Windows Credential
/// Manager on Windows.
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
  /// On Apple platforms this is a ``KeychainLocalStorage`` instance.
  /// On Windows this is a ``WinCredLocalStorage`` instance.
  #if !os(Linux) && !os(Windows) && !os(Android)
    public static let defaultLocalStorage: any AuthLocalStorage = KeychainLocalStorage()
  #elseif os(Windows)
    public static let defaultLocalStorage: any AuthLocalStorage = WinCredLocalStorage()
  #endif
}
