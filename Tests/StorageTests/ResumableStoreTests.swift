import Foundation
import Helpers
import Testing

@testable import Storage

@Suite
struct ResumableStoreTests {
  private let root: URL
  private let container: URL
  private let store: ResumableStore

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    container = root.appendingPathComponent("container")
    try FileManager.default.createDirectory(
      at: container.appendingPathComponent("tmp"), withIntermediateDirectories: true)
    store = ResumableStore(
      directory: root.appendingPathComponent("store"),
      container: container,
      temporaryDirectory: container.appendingPathComponent("tmp"))
  }

  private static let url = URL(string: "http://localhost:54321/storage/v1")!

  private func writeFile(
    _ name: String, in directory: URL? = nil, bytes: Int = 10,
    modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) throws -> URL {
    let url = (directory ?? root).appendingPathComponent(name)
    try Data(repeating: 7, count: bytes).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    return url
  }

  private func record(
    fingerprint: Fingerprint, source: ResumableSource, expiresAt: Date = .distantFuture,
    sourceModificationDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
    totalBytes: Int64 = 10
  ) -> ResumableUploadRecord {
    ResumableUploadRecord(
      fingerprint: fingerprint, bucketID: "bucket", path: "video.mp4", totalBytes: totalBytes,
      source: source, sourceModificationDate: sourceModificationDate,
      uploadURL: URL(string: "http://localhost/upload/resumable/abc")!,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAt: expiresAt,
      lastKnownOffset: 0, chunkSize: 6 << 20, upsert: false, contentType: "video/mp4",
      cacheControl: "max-age=3600", metadata: ["key": "value"])
  }

  /// The file the store keeps for `fingerprint`, spelled out to pin the on-disk names.
  private func storeFile(_ fingerprint: Fingerprint, _ pathExtension: String) -> URL {
    store.directory.appendingPathComponent("\(fingerprint.rawValue).\(pathExtension)")
  }

  @Test
  func fingerprintIgnoresTheURLAndFollowsBucketPathSizeAndDate() throws {
    let a = try writeFile("a.mp4")
    let b = try writeFile("b.mp4")

    let fingerprint = try ResumableStore.fingerprint(
      url: Self.url, bucketID: "bucket", path: "video.mp4", fileURL: a)

    #expect(
      fingerprint
        == (try ResumableStore.fingerprint(
          url: Self.url, bucketID: "bucket", path: "video.mp4", fileURL: b)))
    #expect(fingerprint.rawValue.count == 64)
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: URL(string: "http://other.test/storage/v1")!, bucketID: "bucket", path: "video.mp4",
          fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url, bucketID: "other", path: "video.mp4", fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url, bucketID: "bucket", path: "other.mp4", fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url,
          bucketID: "bucket", path: "video.mp4", fileURL: writeFile("c.mp4", bytes: 11))))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url,
          bucketID: "bucket", path: "video.mp4",
          fileURL: writeFile("d.mp4", modifiedAt: Date(timeIntervalSince1970: 1)))))
  }

  @Test
  func fingerprintOfDataFollowsItsBytes() {
    let fingerprint = ResumableStore.fingerprint(
      url: Self.url,
      bucketID: "bucket", path: "video.mp4", data: Data("abc".utf8))

    #expect(
      fingerprint
        == ResumableStore.fingerprint(
          url: Self.url, bucketID: "bucket", path: "video.mp4", data: Data("abc".utf8))
    )
    #expect(
      fingerprint
        != ResumableStore.fingerprint(
          url: Self.url, bucketID: "bucket", path: "video.mp4", data: Data("abd".utf8))
    )
  }

  @Test
  func saveWritesOneJSONFilePerRecordAndLoadsItBack() throws {
    let file = try writeFile("video.mp4", in: container)
    let record = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))

    try store.save(record)

    #expect(
      FileManager.default.fileExists(atPath: storeFile(.repeating("1"), "json").path)
    )
    #expect(try store.record(fingerprint: .repeating("1")) == record)
    #expect(try store.records() == [record])
    #expect(store.fileURL(for: record) == file)
  }

  @Test
  func missingRecordIsNil() throws {
    #expect(try store.record(fingerprint: .repeating("0")) == nil)
    #expect(try store.records() == [])
  }

  @Test
  func expiredRecordsAreEvicted() throws {
    _ = try writeFile("video.mp4", in: container)
    let record = record(
      fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"),
      expiresAt: Date(timeIntervalSinceNow: -1))
    try store.save(record)

    #expect(try store.record(fingerprint: .repeating("1")) == nil)
    #expect(
      !FileManager.default.fileExists(
        atPath: storeFile(.repeating("1"), "json").path))
  }

  @Test
  func recordsWhoseSourceChangedAreEvicted() throws {
    _ = try writeFile("video.mp4", in: container, modifiedAt: Date(timeIntervalSince1970: 1))
    try store.save(
      record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4")))
    _ = try writeFile("other.mp4", in: container, bytes: 3)
    try store.save(
      record(fingerprint: .repeating("2"), source: .container(relativePath: "other.mp4")))
    try store.save(
      record(fingerprint: .repeating("3"), source: .container(relativePath: "gone.mp4")))

    #expect(try store.records() == [])
  }

  @Test
  func removeDeletesTheRecordAndItsSandboxCopy() throws {
    let source = try store.prepare(data: Data("abc".utf8), fingerprint: .repeating("1"))
    let record = record(
      fingerprint: .repeating("1"), source: source, sourceModificationDate: .distantPast,
      totalBytes: 3)
    try store.save(record)
    let copy = store.fileURL(for: record)
    #expect(FileManager.default.fileExists(atPath: copy.path))

    store.remove(record)

    #expect(try store.record(fingerprint: .repeating("1")) == nil)
    #expect(!FileManager.default.fileExists(atPath: copy.path))
  }

  @Test
  func removingAContainerRecordKeepsAFileNamedLikeASandboxCopy() throws {
    _ = try writeFile("video.mp4", in: container)
    let record = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))
    try store.save(record)
    let other = storeFile(.repeating("1"), "bin")
    try Data("app".utf8).write(to: other)

    store.remove(record)

    #expect(try store.record(fingerprint: .repeating("1")) == nil)
    #expect(FileManager.default.fileExists(atPath: other.path))
  }

  @Test
  func aCorruptRecordIsRemovedWithItsSandboxCopyAndSkipped() throws {
    _ = try writeFile("video.mp4", in: container)
    let good = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))
    try store.save(good)
    let corrupt = storeFile(.repeating("c"), "json")
    let copy = storeFile(.repeating("c"), "bin")
    try Data("{\"fingerprint\":".utf8).write(to: corrupt)
    try Data("abc".utf8).write(to: copy)

    #expect(try store.records() == [good])
    #expect(!FileManager.default.fileExists(atPath: corrupt.path))
    #expect(!FileManager.default.fileExists(atPath: copy.path))
  }

  @Test
  func aJSONFileTheStoreDidNotWriteIsSkippedButKept() throws {
    _ = try writeFile("video.mp4", in: container)
    let good = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))
    try store.save(good)
    let foreign = store.directory.appendingPathComponent("settings.json")
    try Data("{\"theme\":\"dark\"}".utf8).write(to: foreign)

    #expect(try store.records() == [good])
    #expect(FileManager.default.fileExists(atPath: foreign.path))
  }

  @Test
  func aJSONFileNamedLikeAnUppercaseFingerprintIsSkippedButKept() throws {
    _ = try writeFile("video.mp4", in: container)
    let good = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))
    try store.save(good)
    let foreign = store.directory.appendingPathComponent(
      "\(String(repeating: "C", count: 64)).json")
    try Data("{\"fingerprint\":".utf8).write(to: foreign)

    #expect(try store.records() == [good])
    #expect(FileManager.default.fileExists(atPath: foreign.path))
  }

  @Test
  func aRecordWithAMalformedFingerprintIsCorrupt() throws {
    _ = try writeFile("video.mp4", in: container)
    try store.save(
      record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4")))
    let url = storeFile(.repeating("1"), "json")
    let json = try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: Fingerprint.repeating("1").rawValue, with: "f1")
    try Data(json.utf8).write(to: url)

    #expect(try store.records() == [])
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test
  func aRecordThatCannotBeReadIsSkippedButKept() throws {
    _ = try writeFile("video.mp4", in: container)
    let good = record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4"))
    try store.save(good)
    let unreadable = storeFile(.repeating("2"), "json")
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)

    #expect(try store.records() == [good])
    #expect(FileManager.default.fileExists(atPath: unreadable.path))
    #expect(throws: (any Error).self) { try store.record(fingerprint: .repeating("2")) }
  }

  @Test
  func removeAllClearsEveryRecord() throws {
    _ = try writeFile("video.mp4", in: container)
    try store.save(
      record(fingerprint: .repeating("1"), source: .container(relativePath: "video.mp4")))
    try store.save(
      record(fingerprint: .repeating("2"), source: .container(relativePath: "video.mp4")))

    try store.removeAll()

    #expect(try store.records() == [])
  }

  @Test
  func prepareUsesAFileInsideTheContainerInPlace() async throws {
    let file = try writeFile("video.mp4", in: container)

    let source = try await store.prepare(fileURL: file, fingerprint: .repeating("1"))

    #expect(source == .container(relativePath: "video.mp4"))
    #expect(try store.records() == [])
  }

  @Test
  func prepareCopiesAFileOutsideTheContainer() async throws {
    let file = try writeFile("outside.mp4")

    let source = try await store.prepare(fileURL: file, fingerprint: .repeating("1"))

    #expect(source == .sandboxCopy)
    let copy = storeFile(.repeating("1"), "bin")
    #expect(try Data(contentsOf: copy) == Data(contentsOf: file))
  }

  @Test
  func prepareCopiesAFileInTheTemporaryDirectory() async throws {
    let file = try writeFile("picked.mp4", in: container.appendingPathComponent("tmp"))

    let source = try await store.prepare(fileURL: file, fingerprint: .repeating("1"))

    #expect(source == .sandboxCopy)
  }

  @Test
  func prepareDataWritesASandboxCopy() throws {
    let source = try store.prepare(data: Data("abc".utf8), fingerprint: .repeating("1"))

    #expect(source == .sandboxCopy)
    #expect(
      try Data(contentsOf: storeFile(.repeating("1"), "bin")) == Data("abc".utf8))
  }

  @Test
  func defaultDirectoryIsUnderApplicationSupport() {
    let store = ResumableStore()

    #expect(store.directory.path.hasSuffix("io.supabase.storage/resumable"))
  }
}
