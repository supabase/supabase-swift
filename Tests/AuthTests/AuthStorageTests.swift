import Foundation
import Testing

@testable import Auth

@Suite
struct AuthStorageTests {
  @Test
  func savedValueLoadsBack() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.save(Data("session".utf8), key: "key")

    #expect(try await storage.load(key: "key") == Data("session".utf8))
  }

  @Test
  func saveReplacesExistingValue() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.save(Data("old".utf8), key: "key")
    try await storage.save(Data("new".utf8), key: "key")

    #expect(try await storage.load(key: "key") == Data("new".utf8))
  }

  @Test
  func missingKeyLoadsNil() async throws {
    let storage = InMemoryAuthStorage()
    let value = try await storage.load(key: "missing")
    #expect(value == nil)
  }

  @Test
  func removeDeletesOnlyThatKey() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.save(Data("a".utf8), key: "a")
    try await storage.save(Data("b".utf8), key: "b")

    try await storage.remove(key: "a")

    #expect(try await storage.load(key: "a") == nil)
    #expect(try await storage.load(key: "b") == Data("b".utf8))
  }

  @Test
  func removeMissingKeySucceeds() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.remove(key: "missing")
  }

  @Test
  func concurrentAccessKeepsEveryValueWhole() async throws {
    let storage = InMemoryAuthStorage()
    let writers = 50
    let sharedValues = Set((0..<writers).map { Data(repeating: UInt8($0), count: 4096) })

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<writers {
        group.addTask {
          let value = Data(repeating: UInt8(index), count: 4096)
          try await storage.save(value, key: "own-\(index)")
          try await storage.save(value, key: "shared")
          if let shared = try await storage.load(key: "shared") {
            #expect(sharedValues.contains(shared))
          }
        }
      }
      try await group.waitForAll()
    }

    for index in 0..<writers {
      #expect(
        try await storage.load(key: "own-\(index)") == Data(repeating: UInt8(index), count: 4096)
      )
    }
    let shared = try #require(try await storage.load(key: "shared"))
    #expect(sharedValues.contains(shared))
  }
}
