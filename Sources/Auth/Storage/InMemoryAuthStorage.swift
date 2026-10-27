import ConcurrencyExtras
public import Foundation

/// An ``AuthStorage`` that keeps values in memory only.
///
/// Values are lost when the process ends. Use it in tests, in command-line tools that are not
/// signed for Keychain access, and in apps that must not persist a session.
///
/// Copies of an instance share the same values.
public struct InMemoryAuthStorage: AuthStorage {
  let values = LockIsolated<[String: Data]>([:])

  /// Creates an empty in-memory storage.
  public init() {}

  /// Returns the bytes stored under `key`, or `nil` when nothing is stored under it.
  public func load(key: String) async throws -> Data? {
    values.value[key]
  }

  /// Stores `data` under `key`, replacing any value already stored under it.
  public func save(_ data: Data, key: String) async throws {
    values.withValue { $0[key] = data }
  }

  /// Removes the value stored under `key`, if any.
  public func remove(key: String) async throws {
    values.withValue { $0[key] = nil }
  }
}
