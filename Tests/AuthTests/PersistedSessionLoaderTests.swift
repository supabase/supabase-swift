import ConcurrencyExtras
import CustomDump
import Foundation
import Testing

@testable import Auth

@Suite
struct PersistedSessionLoaderTests {
  private let key = "sb-project-auth-token"

  @Test
  func upgradesARealV2SessionFromTheLegacyKeyOnce() async throws {
    let storage = CountingAuthStorage()
    try await storage.save(
      json(named: "persisted-session-v2-camel-case"),
      key: PersistedSessionLoader.legacyKey
    )

    let first = try await PersistedSessionLoader.load(from: storage, key: key)

    expectNoDifference(first?.session, PersistedSessionFixtures.expectedSession)
    #expect(try await storage.load(key: PersistedSessionLoader.legacyKey) == nil)
    let stored = try #require(try await storage.load(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
    expectNoDifference(
      String(decoding: stored, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )

    storage.resetCounts()
    let second = try await PersistedSessionLoader.load(from: storage, key: key)

    expectNoDifference(second, first)
    #expect(storage.loads.value == [key])
    #expect(storage.saves.value.isEmpty)
  }

  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func rewritesAV2ShapeUnderTheKeyOnce(fixture: String) async throws {
    let storage = CountingAuthStorage()
    try await storage.save(json(named: fixture), key: key)
    storage.resetCounts()

    let first = try await PersistedSessionLoader.load(from: storage, key: key)

    expectNoDifference(first?.session, PersistedSessionFixtures.expectedSession)
    #expect(first?.receivedAt == PersistedSessionFixtures.expectedReceivedAt)
    #expect(storage.saves.value == [key])

    storage.resetCounts()
    let second = try await PersistedSessionLoader.load(from: storage, key: key)

    expectNoDifference(second, first)
    #expect(storage.loads.value == [key])
    #expect(storage.saves.value.isEmpty)
  }

  @Test
  func returnsNilWhenNothingIsStored() async throws {
    let storage = CountingAuthStorage()

    let loaded = try await PersistedSessionLoader.load(from: storage, key: key)

    #expect(loaded == nil)
    #expect(storage.saves.value.isEmpty)
  }

  @Test
  func throwsForUndecodableData() async throws {
    let storage = CountingAuthStorage()
    try await storage.save(Data("not-json".utf8), key: key)

    await #expect(throws: DecodingError.self) {
      try await PersistedSessionLoader.load(from: storage, key: key)
    }
  }
}

/// Records each storage call by key.
final class CountingAuthStorage: AuthStorage {
  private let storage = InMemoryAuthStorage()
  let loads = LockIsolated<[String]>([])
  let saves = LockIsolated<[String]>([])

  func load(key: String) async throws -> Data? {
    loads.withValue { $0.append(key) }
    return try await storage.load(key: key)
  }

  func save(_ data: Data, key: String) async throws {
    saves.withValue { $0.append(key) }
    try await storage.save(data, key: key)
  }

  func remove(key: String) async throws {
    try await storage.remove(key: key)
  }

  func resetCounts() {
    loads.setValue([])
    saves.setValue([])
  }
}
