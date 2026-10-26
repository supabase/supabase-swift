import Foundation
import Testing

@testable import Auth

@Suite
struct FileAuthStorageTests {
  @Test
  func createsMissingDirectoryOnFirstSave() async throws {
    try await withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("a/b", isDirectory: true)
      let storage = FileAuthStorage(directory: directory)

      try await storage.save(Data("session".utf8), key: "key")

      #expect(try await storage.load(key: "key") == Data("session".utf8))
      #expect(try contents(of: directory).count == 1)
    }
  }

  #if !os(Windows)
    @Test
    func filesAreReadableByOwnerOnly() async throws {
      try await withTemporaryDirectory { directory in
        let storage = FileAuthStorage(directory: directory)

        try await storage.save(Data("first".utf8), key: "key")
        try await storage.save(Data("second".utf8), key: "key")

        let files = try contents(of: directory)
        #expect(files.count == 1)
        let file = try #require(files.first)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
      }
    }

    @Test
    func createdDirectoryIsReadableByOwnerOnly() async throws {
      try await withTemporaryDirectory { root in
        let directory = root.appendingPathComponent("auth", isDirectory: true)

        try await FileAuthStorage(directory: directory).save(Data(), key: "key")

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
      }
    }
  #endif

  @Test(arguments: ["../escape", "/etc/passwd", "a/b/c", ".", "..", ""])
  func keysStayInsideTheDirectory(_ key: String) async throws {
    try await withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("auth", isDirectory: true)
      let storage = FileAuthStorage(directory: directory)

      try await storage.save(Data("session".utf8), key: key)

      #expect(try await storage.load(key: key) == Data("session".utf8))
      #expect(try contents(of: root).map(\.lastPathComponent) == ["auth"])
      let files = try contents(of: directory)
      #expect(files.count == 1)
      let file = try #require(files.first)
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      #expect(attributes[.type] as? FileAttributeType == .typeRegular)
    }
  }

  @Test
  func keysThatDifferOnlyInCaseDoNotCollide() async throws {
    try await withTemporaryDirectory { directory in
      let storage = FileAuthStorage(directory: directory)

      try await storage.save(Data("lower".utf8), key: "key")
      try await storage.save(Data("upper".utf8), key: "KEY")

      #expect(try await storage.load(key: "key") == Data("lower".utf8))
      #expect(try await storage.load(key: "KEY") == Data("upper".utf8))
    }
  }

  @Test
  func instancesSharingADirectorySeeEachOthersWrites() async throws {
    try await withTemporaryDirectory { directory in
      try await FileAuthStorage(directory: directory).save(Data("session".utf8), key: "key")

      #expect(
        try await FileAuthStorage(directory: directory).load(key: "key") == Data("session".utf8))
    }
  }

  private func contents(of directory: URL) throws -> [URL] {
    try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
  }

  private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("FileAuthStorageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
  }
}
