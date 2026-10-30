import Foundation

/// The configured ``AuthLocalStorage`` as an ``AuthStorage``, so ``SessionStore`` can own the
/// session while ``AuthClient/Configuration/localStorage`` stays synchronous.
struct AuthLocalStorageAdapter: AuthStorage {
  let localStorage: any AuthLocalStorage

  func load(key: String) async throws -> Data? {
    try localStorage.retrieve(key: key)
  }

  func save(_ data: Data, key: String) async throws {
    try localStorage.store(key: key, value: data)
  }

  func remove(key: String) async throws {
    try localStorage.remove(key: key)
  }
}
