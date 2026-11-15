//
//  StorageResumableIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 15/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
@_spi(Experimental) import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageResumableIntegrationTests {
  static let fileSize = 20 << 20

  let bucketName: String
  let directory: URL
  let fileURL: URL

  init() async throws {
    bucketName = try await StorageIntegration.newBucket("resumable")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    directory = root.appendingPathComponent("store")
    fileURL = root.appendingPathComponent("big.bin")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Self.writeFixture(to: fileURL)
  }

  deinit {
    StorageIntegration.dropBucket(bucketName)
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }

  private static func writeFixture(to url: URL) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let piece = 1 << 20
    for index in 0..<(fileSize / piece) {
      handle.write(Data((0..<piece).map { UInt8(truncatingIfNeeded: ($0 &+ index) &* 31) }))
    }
  }

  private func client(
    transport: FailingTransport? = nil, retryTimeout: Duration = .seconds(60)
  ) throws -> StorageClient {
    var configuration = StorageClient.Configuration(
      url: StorageIntegration.url,
      headers: [.authorization: "Bearer \(DotEnv.supabaseSecretKey)"])
    if let transport { configuration.http = .init(transport: transport.transport) }
    configuration.resumable = ResumableUploadConfiguration(
      retryTimeout: retryTimeout, directory: directory)
    return try StorageClient(configuration: configuration)
  }

  /// Sends requests to the local stack. Fails each request whose method is in `failing` as a
  /// dropped connection would, since a live server cannot drop one on cue, and holds each `HEAD`
  /// while `holdHead` is set.
  private final class FailingTransport: Sendable {
    let failing = LockIsolated<Set<HTTPRequest.Method>>([])
    let sent = LockIsolated<[HTTPRequest.Method]>([])
    let holdHead = LockIsolated<AsyncStream<Void>?>(nil)

    var transport: ClosureTransport {
      let base = URLSessionTransport()
      return ClosureTransport { [failing, sent, holdHead] request, body in
        sent.withValue { $0.append(request.method) }
        if failing.value.contains(request.method) { throw URLError(.networkConnectionLost) }
        if request.method == .head, let gate = holdHead.value {
          for await _ in gate { break }
        }
        return try await base.send(request, body: body)
      }
    }

    func count(_ method: HTTPRequest.Method) -> Int { sent.value.filter { $0 == method }.count }
  }

  private func bucket(_ client: StorageClient) -> StorageBucket {
    client.from(bucketName)
  }

  private func waitForFirstChunk(of upload: ResumableUpload) async {
    for await progress in upload.progress() where progress.completedBytes > 0 { return }
  }

  private func expectObject(_ client: StorageClient, path: String) async throws {
    let info = try await bucket(client).info(path: path)
    #expect(info.size == Int64(Self.fileSize))
    let downloaded = try await bucket(client).download(path: path).data()
    #expect(downloaded == (try Data(contentsOf: fileURL)))
  }

  @Test
  func uploadsALargeFileInChunks() async throws {
    let client = try client()
    let upload = try bucket(client).resumableUpload(path: "whole.bin", fileURL: fileURL)
    let progress = upload.progress()
    var statuses = upload.statusChanges().makeAsyncIterator()
    guard case .pending? = await statuses.next() else {
      Issue.record("a new upload's status stream starts with .pending"); return
    }

    try await upload.start()
    let object = try await upload.result

    #expect(object.fullPath == "\(bucketName)/whole.bin")
    var last: Int64 = 0
    for await report in progress {
      #expect(report.completedBytes >= last)
      #expect(report.totalBytes == Int64(Self.fileSize))
      last = report.completedBytes
    }
    #expect(last == Int64(Self.fileSize))
    try await expectObject(client, path: "whole.bin")
    #expect(try await client.resumableUploads.pending().isEmpty)
  }

  @Test
  func pauseThenResumeFinishesTheUpload() async throws {
    let client = try client()
    let upload = try bucket(client).resumableUpload(path: "paused.bin", fileURL: fileURL)

    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.pause()
    guard case .paused = await upload.status else {
      Issue.record("Expected a paused upload")
      return
    }
    #expect(try await client.resumableUploads.pending().count == 1)

    try await upload.resume()
    _ = try await upload.result

    try await expectObject(client, path: "paused.bin")
    #expect(try await client.resumableUploads.pending().isEmpty)
  }

  @Test
  func cancelRemovesTheUploadAndItsRecord() async throws {
    let client = try client()
    let upload = try bucket(client).resumableUpload(path: "cancelled.bin", fileURL: fileURL)

    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.cancel()

    guard case .cancelled = await upload.status else {
      Issue.record("Expected a cancelled upload")
      return
    }
    await #expect(throws: CancellationError.self) { try await upload.result }
    #expect(try await client.resumableUploads.pending().isEmpty)
    #expect(try await bucket(client).exists(path: "cancelled.bin") == false)
  }

  @Test
  func everyConcurrentCancelReturnsAfterTheRecordIsGone() async throws {
    let client = try client()
    let upload = try bucket(client).resumableUpload(path: "cancelled-twice.bin", fileURL: fileURL)
    try await upload.start()
    await waitForFirstChunk(of: upload)

    async let first = Self.cancelThenCountPending(upload, client)
    async let second = Self.cancelThenCountPending(upload, client)

    let pendingAfterEachCancel: [Int] = try await [first, second]
    #expect(pendingAfterEachCancel == [0, 0])
    #expect(try await bucket(client).exists(path: "cancelled-twice.bin") == false)
  }

  private static func cancelThenCountPending(_ upload: ResumableUpload, _ client: StorageClient)
    async throws -> Int
  {
    await upload.cancel()
    return try await client.resumableUploads.pending().count
  }

  @Test
  func aSecondClientResumesFromTheRecord() async throws {
    let first = try client()
    let upload = try bucket(first).resumableUpload(path: "relaunched.bin", fileURL: fileURL)
    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.pause()

    let second = try client()
    let resumed = try await second.resumableUploads.resumeAll()
    #expect(resumed.count == 1)
    #expect(resumed.first?.id == upload.id)
    _ = try await resumed[0].result

    try await expectObject(second, path: "relaunched.bin")
    #expect(try await second.resumableUploads.pending().isEmpty)
  }

  @Test
  func aCorruptRecordDoesNotBlockRelaunchRecovery() async throws {
    let first = try client()
    let upload = try bucket(first).resumableUpload(path: "corrupt-neighbor.bin", fileURL: fileURL)
    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.pause()
    let corrupt = directory.appendingPathComponent("\(String(repeating: "c", count: 64)).json")
    try Data("{".utf8).write(to: corrupt)

    let second = try client()
    let resumed = try await second.resumableUploads.resumeAll()
    #expect(resumed.map(\.id) == [upload.id])
    _ = try await resumed[0].result

    try await expectObject(second, path: "corrupt-neighbor.bin")
    #expect(!FileManager.default.fileExists(atPath: corrupt.path))
  }

  @Test
  func resumeAfterAFailedStartCreatesTheUpload() async throws {
    let transport = FailingTransport()
    let client = try client(transport: transport)
    let upload = try bucket(client).resumableUpload(path: "failed-start.bin", fileURL: fileURL)
    transport.failing.setValue([.post])
    let error = await #expect(throws: StorageError.self) { try await upload.start() }
    #expect(error?.kind == .transport)
    transport.failing.setValue([])

    try await upload.resume()
    _ = try await upload.result

    try await expectObject(client, path: "failed-start.bin")
    #expect(try await client.resumableUploads.pending().isEmpty)
  }

  @Test
  func cancelOnAPendingHandleLeavesTheUploadAnotherHandleResumes() async throws {
    let transport = FailingTransport()
    let client = try client(transport: transport, retryTimeout: .zero)
    let upload = try bucket(client).resumableUpload(path: "shared-record.bin", fileURL: fileURL)
    transport.failing.setValue([.patch])
    try await upload.start()
    await #expect(throws: StorageError.self) { try await upload.result }
    transport.failing.setValue([])
    let other = try #require(try await client.resumableUploads.pending().first)
    #expect(other !== upload)

    let (gate, open) = AsyncStream<Void>.makeStream()
    transport.holdHead.setValue(gate)
    try await upload.resume()
    await other.cancel()
    open.finish()
    _ = try await upload.result

    #expect(transport.count(.delete) == 0, "cancel() left the server upload the resume drives")
    #expect(transport.count(.post) == 1, "the upload was never created again")
    try await expectObject(client, path: "shared-record.bin")
  }
}
