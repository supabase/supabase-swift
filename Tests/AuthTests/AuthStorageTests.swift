import Foundation
import Testing

@testable import Auth

@Suite
struct AuthStorageTests {
  enum Implementation: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case file

    var testDescription: String { rawValue }
  }

  @Test(arguments: Implementation.allCases)
  func savedValueLoadsBack(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
      try await storage.save(Data("session".utf8), key: "key")

      #expect(try await storage.load(key: "key") == Data("session".utf8))
    }
  }

  @Test(arguments: Implementation.allCases)
  func saveReplacesExistingValue(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
      try await storage.save(Data("old".utf8), key: "key")
      try await storage.save(Data("new".utf8), key: "key")

      #expect(try await storage.load(key: "key") == Data("new".utf8))
    }
  }

  @Test(arguments: Implementation.allCases)
  func missingKeyLoadsNil(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
      let value = try await storage.load(key: "missing")
      #expect(value == nil)
    }
  }

  @Test(arguments: Implementation.allCases)
  func removeDeletesOnlyThatKey(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
      try await storage.save(Data("a".utf8), key: "a")
      try await storage.save(Data("b".utf8), key: "b")

      try await storage.remove(key: "a")

      #expect(try await storage.load(key: "a") == nil)
      #expect(try await storage.load(key: "b") == Data("b".utf8))
    }
  }

  @Test(arguments: Implementation.allCases)
  func removeMissingKeySucceeds(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
      try await storage.remove(key: "missing")
    }
  }

  @Test(arguments: Implementation.allCases)
  func concurrentAccessKeepsEveryValueWhole(_ implementation: Implementation) async throws {
    try await withStorage(implementation) { storage in
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

  private func withStorage(
    _ implementation: Implementation,
    _ body: (any AuthStorage) async throws -> Void
  ) async throws {
    switch implementation {
    case .inMemory:
      try await body(InMemoryAuthStorage())
    case .file:
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AuthStorageTests-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      try await body(FileAuthStorage(directory: directory))
    }
  }
}
