package import Auth
import ConcurrencyExtras
package import Foundation

/// An ``AuthStorage`` that keeps values in memory and lets a test read and seed them without
/// awaiting.
package final class InMemoryTestStorage: AuthStorage, @unchecked Sendable {
  let _storage = LockIsolated([String: Data]())

  package var storage: [String: Data] {
    _storage.value
  }

  package init() {}

  package func load(key: String) async throws -> Data? {
    retrieve(key: key)
  }

  package func save(_ data: Data, key: String) async throws {
    store(key: key, value: data)
  }

  package func remove(key: String) async throws {
    _storage.withValue {
      $0[key] = nil
    }
  }

  package func store(key: String, value: Data) {
    _storage.withValue {
      $0[key] = value
    }
  }

  package func retrieve(key: String) -> Data? {
    _storage.value[key]
  }
}
