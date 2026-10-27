import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct StorageIdentityTests {
  @Test
  func copiesOfOneInMemoryStorageHaveOneIdentity() {
    let storage = InMemoryAuthStorage()
    let copy = storage

    #expect(StorageIdentity(of: storage) == StorageIdentity(of: copy))
    #expect(StorageIdentity(of: storage) != StorageIdentity(of: InMemoryAuthStorage()))
  }

  @Test
  func classStorageIsIdentifiedByItsInstance() {
    let storage = InMemoryLocalStorage()

    #expect(
      StorageIdentity(of: AuthLocalStorageAdapter(localStorage: storage))
        == StorageIdentity(of: storage))
    #expect(StorageIdentity(of: storage) != StorageIdentity(of: InMemoryLocalStorage()))
  }

  @Test
  func valueStorageHasNoIdentity() {
    #expect(StorageIdentity(of: ValueLocalStorage()) == nil)
  }

  #if canImport(Security)
    @Test
    func keychainStoragesForTheSameItemsHaveOneIdentity() {
      #expect(StorageIdentity(of: KeychainLocalStorage()) != nil)
      #expect(
        StorageIdentity(of: KeychainLocalStorage()) == StorageIdentity(of: KeychainLocalStorage()))
      #expect(
        StorageIdentity(of: KeychainLocalStorage(service: "a"))
          != StorageIdentity(of: KeychainLocalStorage(service: "b")))
      #expect(
        StorageIdentity(of: KeychainLocalStorage(accessGroup: "group"))
          != StorageIdentity(of: KeychainLocalStorage()))
    }
  #endif
}

private struct ValueLocalStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws {}
  func retrieve(key: String) throws -> Data? { nil }
  func remove(key: String) throws {}
}
