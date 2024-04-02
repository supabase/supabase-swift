import Auth
import ConcurrencyExtras
import Foundation

package final class InMemoryLocalStorage: AuthLocalStorage, @unchecked Sendable {
  let _storage = LockIsolated([String: Data]())

  package var storage: [String: Data] {
    _storage.value
  }

  package init() {}

  package func store(key: String, value: Data) throws {
    _storage.withValue {
      $0[key] = value
    }
  }

  package func retrieve(key: String) throws -> Data? {
    _storage.value[key]
  }

  package func remove(key: String) throws {
    _storage.withValue {
      $0[key] = nil
    }
  }
}
