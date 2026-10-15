//
//  StorageResumableIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 15/10/26.
//

import Foundation
import Helpers
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Resumable uploads against a live Storage: a chunked upload, pause and resume, cancel, and a
/// second client continuing from the record.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageResumableIntegrationTests {
  /// 20 MiB: four chunks at the 6 MiB hosted Supabase requires, the last one short.
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

  /// Non-constant bytes, written in 1 MiB pieces so the fixture never sits in memory whole.
  private static func writeFixture(to url: URL) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let piece = 1 << 20
    for index in 0..<(fileSize / piece) {
      handle.write(Data((0..<piece).map { UInt8(truncatingIfNeeded: ($0 &+ index) &* 31) }))
    }
  }

  /// A client whose records live in this test's directory, so a second one can find them.
  private func client() -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: StorageIntegration.url,
        headers: [.authorization: "Bearer \(DotEnv.supabaseSecretKey)"],
        resumable: ResumableUploadConfiguration(directory: directory)))
  }

  private func bucket(_ client: StorageClient) -> StorageBucket {
    client.from(bucketName)
  }

  /// Returns once the server has confirmed at least one chunk.
  private func waitForFirstChunk(of upload: ResumableUpload) async {
    for await progress in upload.progress where progress.completedBytes > 0 { return }
  }

  private func expectObject(_ client: StorageClient, path: String) async throws {
    let info = try await bucket(client).info(path: path)
    #expect(info.size == Int64(Self.fileSize))
    let downloaded = try await bucket(client).download(path: path).data()
    #expect(downloaded == (try Data(contentsOf: fileURL)))
  }

  @Test
  func uploadsALargeFileInChunks() async throws {
    let client = client()
    let upload = try bucket(client).resumableUpload(path: "whole.bin", fileURL: fileURL)
    let progress = upload.progress

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
    #expect(try client.resumableUploads.pending().isEmpty)
  }

  @Test
  func pauseThenResumeFinishesTheUpload() async throws {
    let client = client()
    let upload = try bucket(client).resumableUpload(path: "paused.bin", fileURL: fileURL)

    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.pause()
    guard case .paused = await upload.state else {
      Issue.record("Expected a paused upload")
      return
    }
    #expect(try client.resumableUploads.pending().count == 1)

    try await upload.resume()
    _ = try await upload.result

    try await expectObject(client, path: "paused.bin")
    #expect(try client.resumableUploads.pending().isEmpty)
  }

  @Test
  func cancelRemovesTheUploadAndItsRecord() async throws {
    let client = client()
    let upload = try bucket(client).resumableUpload(path: "cancelled.bin", fileURL: fileURL)

    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.cancel()

    guard case .cancelled = await upload.state else {
      Issue.record("Expected a cancelled upload")
      return
    }
    await #expect(throws: CancellationError.self) { try await upload.result }
    #expect(try client.resumableUploads.pending().isEmpty)
    #expect(try await bucket(client).exists(path: "cancelled.bin") == false)
  }

  @Test
  func aSecondClientResumesFromTheRecord() async throws {
    let first = client()
    let upload = try bucket(first).resumableUpload(path: "relaunched.bin", fileURL: fileURL)
    try await upload.start()
    await waitForFirstChunk(of: upload)
    await upload.pause()

    let second = client()
    let resumed = try await second.resumableUploads.resumeAll()
    #expect(resumed.count == 1)
    #expect(resumed.first?.id == upload.id)
    _ = try await resumed[0].result

    try await expectObject(second, path: "relaunched.bin")
    #expect(try second.resumableUploads.pending().isEmpty)
  }
}
