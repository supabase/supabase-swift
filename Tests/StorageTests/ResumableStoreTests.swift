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
    fingerprint: String, source: ResumableSource, expiresAt: Date = .distantFuture,
    sourceModificationDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
    totalBytes: Int64 = 10
  ) -> ResumableUploadRecord {
    ResumableUploadRecord(
      fingerprint: fingerprint, bucketId: "bucket", path: "video.mp4", totalBytes: totalBytes,
      source: source, sourceModificationDate: sourceModificationDate,
      uploadURL: URL(string: "http://localhost/upload/resumable/abc")!,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAt: expiresAt,
      lastKnownOffset: 0, chunkSize: 6 << 20, upsert: false, contentType: "video/mp4",
      cacheControl: "max-age=3600", metadata: ["key": "value"])
  }

  // MARK: - Fingerprint

  @Test
  func fingerprintIgnoresTheURLAndFollowsBucketPathSizeAndDate() throws {
    let a = try writeFile("a.mp4")
    let b = try writeFile("b.mp4")

    let fingerprint = try ResumableStore.fingerprint(
      url: Self.url, bucketId: "bucket", path: "video.mp4", fileURL: a)

    #expect(
      fingerprint
        == (try ResumableStore.fingerprint(
          url: Self.url, bucketId: "bucket", path: "video.mp4", fileURL: b)))
    #expect(fingerprint.count == 64)
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: URL(string: "http://other.test/storage/v1")!, bucketId: "bucket", path: "video.mp4",
          fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url, bucketId: "other", path: "video.mp4", fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url, bucketId: "bucket", path: "other.mp4", fileURL: a)))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url,
          bucketId: "bucket", path: "video.mp4", fileURL: writeFile("c.mp4", bytes: 11))))
    #expect(
      fingerprint
        != (try ResumableStore.fingerprint(
          url: Self.url,
          bucketId: "bucket", path: "video.mp4",
          fileURL: writeFile("d.mp4", modifiedAt: Date(timeIntervalSince1970: 1)))))
  }

  @Test
  func fingerprintOfDataFollowsItsBytes() {
    let fingerprint = ResumableStore.fingerprint(
      url: Self.url,
      bucketId: "bucket", path: "video.mp4", data: Data("abc".utf8))

    #expect(
      fingerprint
        == ResumableStore.fingerprint(
          url: Self.url, bucketId: "bucket", path: "video.mp4", data: Data("abc".utf8))
    )
    #expect(
      fingerprint
        != ResumableStore.fingerprint(
          url: Self.url, bucketId: "bucket", path: "video.mp4", data: Data("abd".utf8))
    )
  }

  // MARK: - Records

  @Test
  func saveWritesOneJSONFilePerRecordAndLoadsItBack() throws {
    let file = try writeFile("video.mp4", in: container)
    let record = record(fingerprint: "f1", source: .container(relativePath: "video.mp4"))

    try store.save(record)

    #expect(
      FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("f1.json").path)
    )
    #expect(try store.record(fingerprint: "f1") == record)
    #expect(try store.records() == [record])
    #expect(store.fileURL(for: record) == file)
  }

  @Test
  func missingRecordIsNil() throws {
    #expect(try store.record(fingerprint: "nope") == nil)
    #expect(try store.records() == [])
  }

  @Test
  func expiredRecordsAreEvicted() throws {
    _ = try writeFile("video.mp4", in: container)
    let record = record(
      fingerprint: "f1", source: .container(relativePath: "video.mp4"),
      expiresAt: Date(timeIntervalSinceNow: -1))
    try store.save(record)

    #expect(try store.record(fingerprint: "f1") == nil)
    #expect(
      !FileManager.default.fileExists(
        atPath: store.directory.appendingPathComponent("f1.json").path))
  }

  @Test
  func recordsWhoseSourceChangedAreEvicted() throws {
    _ = try writeFile("video.mp4", in: container, modifiedAt: Date(timeIntervalSince1970: 1))
    try store.save(record(fingerprint: "f1", source: .container(relativePath: "video.mp4")))
    _ = try writeFile("other.mp4", in: container, bytes: 3)
    try store.save(record(fingerprint: "f2", source: .container(relativePath: "other.mp4")))
    try store.save(record(fingerprint: "f3", source: .container(relativePath: "gone.mp4")))

    #expect(try store.records() == [])
  }

  @Test
  func removeDeletesTheRecordAndItsSandboxCopy() throws {
    let source = try store.prepare(data: Data("abc".utf8), fingerprint: "f1")
    let record = record(
      fingerprint: "f1", source: source, sourceModificationDate: .distantPast, totalBytes: 3)
    try store.save(record)
    let copy = store.fileURL(for: record)
    #expect(FileManager.default.fileExists(atPath: copy.path))

    try store.remove(record)

    #expect(try store.record(fingerprint: "f1") == nil)
    #expect(!FileManager.default.fileExists(atPath: copy.path))
  }

  @Test
  func removeAllClearsEveryRecord() throws {
    _ = try writeFile("video.mp4", in: container)
    try store.save(record(fingerprint: "f1", source: .container(relativePath: "video.mp4")))
    try store.save(record(fingerprint: "f2", source: .container(relativePath: "video.mp4")))

    try store.removeAll()

    #expect(try store.records() == [])
  }

  // MARK: - Sources

  @Test
  func prepareUsesAFileInsideTheContainerInPlace() async throws {
    let file = try writeFile("video.mp4", in: container)

    let source = try await store.prepare(fileURL: file, fingerprint: "f1")

    #expect(source == .container(relativePath: "video.mp4"))
    #expect(try store.records() == [])
  }

  @Test
  func prepareCopiesAFileOutsideTheContainer() async throws {
    let file = try writeFile("outside.mp4")

    let source = try await store.prepare(fileURL: file, fingerprint: "f1")

    #expect(source == .sandboxCopy)
    let copy = store.directory.appendingPathComponent("f1.bin")
    #expect(try Data(contentsOf: copy) == Data(contentsOf: file))
  }

  @Test
  func prepareCopiesAFileInTheTemporaryDirectory() async throws {
    let file = try writeFile("picked.mp4", in: container.appendingPathComponent("tmp"))

    let source = try await store.prepare(fileURL: file, fingerprint: "f1")

    #expect(source == .sandboxCopy)
  }

  @Test
  func prepareDataWritesASandboxCopy() throws {
    let source = try store.prepare(data: Data("abc".utf8), fingerprint: "f1")

    #expect(source == .sandboxCopy)
    #expect(
      try Data(contentsOf: store.directory.appendingPathComponent("f1.bin")) == Data("abc".utf8))
  }

  @Test
  func defaultDirectoryIsUnderApplicationSupport() {
    let store = ResumableStore()

    #expect(store.directory.path.hasSuffix("io.supabase.storage/resumable"))
  }
}
