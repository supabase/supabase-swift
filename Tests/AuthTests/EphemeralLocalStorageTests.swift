import Foundation
import Testing

@testable import Auth

@Suite
struct EphemeralLocalStorageTests {
  @Test
  func storedValueRetrievesBack() throws {
    let storage = EphemeralLocalStorage()
    try storage.store(key: "key", value: Data("session".utf8))

    #expect(try storage.retrieve(key: "key") == Data("session".utf8))
  }

  @Test
  func missingKeyRetrievesNil() throws {
    #expect(try EphemeralLocalStorage().retrieve(key: "missing") == nil)
  }

  @Test
  func removeDeletesOnlyThatKey() throws {
    let storage = EphemeralLocalStorage()
    try storage.store(key: "a", value: Data("a".utf8))
    try storage.store(key: "b", value: Data("b".utf8))

    try storage.remove(key: "a")

    #expect(try storage.retrieve(key: "a") == nil)
    #expect(try storage.retrieve(key: "b") == Data("b".utf8))
  }
}
