import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct ResumableUploadRegistryTests {
  private let root: URL
  private let fileURL: URL
  private let requests = LockIsolated<[String]>([])
  private let responses = LockIsolated<[(HTTPResponse, Data)]>([])

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    fileURL = root.appendingPathComponent("video.mp4")
    try Data(repeating: 1, count: 20).write(to: fileURL)
  }

  private var storage: StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { [requests, responses] request, _ in
            requests.withValue { $0.append("\(request.method.rawValue) \(request.path ?? "")") }
            guard
              let (response, body) = responses.withValue({ $0.isEmpty ? nil : $0.removeFirst() })
            else {
              try await Task.sleep(for: .seconds(60))
              throw URLError(.cancelled)
            }
            return (response, body.isEmpty ? nil : HTTPBody(body))
          }),
        resumable: ResumableUploadConfiguration(
          chunkSize: 8, directory: root.appendingPathComponent("store"))))
  }

  private var store: ResumableStore {
    ResumableStore(directory: root.appendingPathComponent("store"))
  }

  private func saveRecord(fingerprint: String, offset: Int64 = 8) throws -> ResumableUploadRecord {
    let source = try store.prepare(data: Data(repeating: 1, count: 20), fingerprint: fingerprint)
    let record = ResumableUploadRecord(
      fingerprint: fingerprint, bucketId: "bucket", path: "video.mp4", totalBytes: 20,
      source: source, sourceModificationDate: .distantPast,
      uploadURL: URL(string: "http://localhost:54321/storage/v1/upload/resumable/\(fingerprint)")!,
      createdAt: Date(), expiresAt: .distantFuture, lastKnownOffset: offset, chunkSize: 8,
      upsert: true, contentType: "video/mp4", cacheControl: "max-age=1", metadata: nil)
    try store.save(record)
    return record
  }

  private func respond(_ status: HTTPResponse.Status, headers: HTTPFields = [:], body: String = "")
  {
    responses.withValue {
      $0.append((HTTPResponse(status: status, headerFields: headers), Data(body.utf8)))
    }
  }

  @Test
  func pendingReturnsAHandlePerRecordOldestFirst() throws {
    let a = try saveRecord(fingerprint: "a")
    _ = try saveRecord(fingerprint: "b")

    let uploads = try storage.resumableUploads.pending()

    #expect(uploads.map(\.id.rawValue) == ["a", "b"])
    #expect(uploads[0].bucketId == a.bucketId)
    #expect(uploads[0].path == a.path)
    #expect(uploads[0].totalBytes == 20)
  }

  @Test
  func pendingReturnsTheHandleAlreadyInFlight() async throws {
    respond(.created, headers: [.location: "/storage/v1/upload/resumable/x", .uploadOffset: "0"])
    let upload = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await upload.start()

    let pending = try storage.resumableUploads.pending()

    #expect(pending.count == 1)
    #expect(pending.first === upload)
    respond(.noContent)
    await upload.cancel()
  }

  @Test
  func resumableUploadReturnsTheHandleAlreadyInFlightForTheSameFile() async throws {
    respond(.created, headers: [.location: "/storage/v1/upload/resumable/x", .uploadOffset: "0"])
    let first = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await first.start()

    let second = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)

    #expect(second === first)
    respond(.noContent)
    await first.cancel()
    let third = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)
    #expect(third !== first)
  }

  @Test
  func resumeAllContinuesEveryRecordFromTheServerOffset() async throws {
    _ = try saveRecord(fingerprint: "a")
    respond(.ok, headers: [.uploadOffset: "8"])
    respond(.noContent, headers: [.uploadOffset: "16"])
    respond(.noContent, headers: [.uploadOffset: "20", .tusComplete: "1"])

    let uploads = try await storage.resumableUploads.resumeAll()
    let object = try await uploads[0].result

    #expect(object.fullPath == "bucket/video.mp4")
    #expect(
      requests.value == [
        "HEAD /storage/v1/upload/resumable/a",
        "PATCH /storage/v1/upload/resumable/a",
        "PATCH /storage/v1/upload/resumable/a",
      ])
    #expect(try store.records().isEmpty)
  }

  @Test
  func clearKeepsTheUploadInFlight() async throws {
    _ = try saveRecord(fingerprint: "a")
    respond(.created, headers: [.location: "/storage/v1/upload/resumable/x", .uploadOffset: "0"])
    let upload = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await upload.start()
    let record = try #require(try store.record(fingerprint: upload.id.rawValue))

    try storage.resumableUploads.clear()

    #expect(try store.records().map(\.fingerprint) == [upload.id.rawValue])
    #expect(FileManager.default.fileExists(atPath: store.fileURL(for: record).path))
    respond(.noContent)
    await upload.cancel()
  }

  @Test
  func clearRemovesTheRecordsOfHandlesThatNeverStarted() throws {
    _ = try saveRecord(fingerprint: "a")
    let pending = try storage.resumableUploads.pending()

    try storage.resumableUploads.clear()

    #expect(try store.records().isEmpty)
    withExtendedLifetime(pending) {}
  }

  @Test
  func aHandleThatNeverStartsIsReleased() throws {
    weak var released: ResumableUpload?
    do {
      let upload = try storage.from("bucket").resumableUpload(path: "video.mp4", fileURL: fileURL)
      released = upload
      #expect(released != nil)
    }
    #expect(released == nil)
  }

  @Test
  func clearRemovesEveryRecord() throws {
    _ = try saveRecord(fingerprint: "a")
    _ = try saveRecord(fingerprint: "b")

    try storage.resumableUploads.clear()

    #expect(try storage.resumableUploads.pending().isEmpty)
  }
}
