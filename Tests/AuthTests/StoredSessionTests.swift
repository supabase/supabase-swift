import CustomDump
import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct StoredSessionTests {
  private let key = "supabase.auth.token"

  @Test
  func get_withCorruptedJSON_returnsNil() throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(key: key, value: Data("not-valid-json".utf8))

    #expect(makeSUT(localStorage).get() == nil)
  }

  @Test
  func storedSessionLoadsBackUnchanged() throws {
    let localStorage = InMemoryLocalStorage()
    let sut = makeSUT(localStorage)

    sut.store(.valid)

    expectNoDifference(sut.get(), .valid)
    let stored = try #require(try localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func rewritesAV2ShapeAsSchema1(fixture: String) throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(key: key, value: json(named: fixture))

    expectNoDifference(makeSUT(localStorage).get(), PersistedSessionFixtures.expectedSession)

    let stored = try #require(try localStorage.retrieve(key: key))
    expectNoDifference(
      String(decoding: stored, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )
  }

  @Test
  func movesASessionFromTheLegacyKey() throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(
      key: PersistedSessionLoader.legacyKey,
      value: json(named: "persisted-session-v2-camel-case")
    )

    expectNoDifference(makeSUT(localStorage).get(), PersistedSessionFixtures.expectedSession)

    #expect(try localStorage.retrieve(key: PersistedSessionLoader.legacyKey) == nil)
    let stored = try #require(try localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test
  func checksTheLegacyKeyOncePerInstance() throws {
    let localStorage = InMemoryLocalStorage()
    let sut = makeSUT(localStorage)
    #expect(sut.get() == nil)

    try localStorage.store(
      key: PersistedSessionLoader.legacyKey,
      value: json(named: "persisted-session-v2-camel-case")
    )

    #expect(sut.get() == nil)
  }

  private func makeSUT(_ localStorage: InMemoryLocalStorage) -> SessionStorage {
    SessionStorage.live(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost")!,
        storageKey: key,
        localStorage: localStorage
      )
    )
  }
}
