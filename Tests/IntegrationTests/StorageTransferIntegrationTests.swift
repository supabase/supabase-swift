//
//  StorageTransferIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 13/10/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Uploads and downloads against a live Storage: progress, streamed bodies, ranges and files.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageTransferIntegrationTests {
  let bucketName: String
  let bucket: StorageBucket
  /// 4 MiB of non-repeating bytes, big enough for `URLSession` to report progress more than once.
  let payload = Data((0..<(4 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) })

  init() async throws {
    bucketName = try await StorageIntegration.newBucket("transfer")
    bucket = StorageIntegration.admin.from(bucketName)
  }

  deinit {
    StorageIntegration.dropBucket(bucketName)
  }

  /// Records every progress call, for checking it rises and ends on the total.
  final class ProgressLog: Sendable {
    let reports = LockIsolated<[TransferProgress]>([])

    var callback: @Sendable (TransferProgress) -> Void {
      { [reports] progress in reports.withValue { $0.append(progress) } }
    }

    func expectRisesTo(_ total: Int64, sourceLocation: SourceLocation = #_sourceLocation) {
      let completed = reports.value.map(\.completedBytes)
      #expect(!completed.isEmpty, sourceLocation: sourceLocation)
      #expect(completed == completed.sorted(), sourceLocation: sourceLocation)
      #expect(
        reports.value.last == TransferProgress(completedBytes: total, totalBytes: total),
        sourceLocation: sourceLocation)
    }
  }

  private func temporaryFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("transfer-\(UUID().uuidString).bin")
    try data.write(to: url)
    return url
  }

  // MARK: - Upload progress

  @Test
  func uploadFromDataReportsProgressUpToItsSize() async throws {
    let log = ProgressLog()

    try await bucket.upload(path: "data.bin", data: payload, progress: log.callback)

    log.expectRisesTo(Int64(payload.count))
    #expect(try await bucket.info(path: "data.bin").size == Int64(payload.count))
  }

  @Test
  func updateFromAFileReportsProgressUpToItsSize() async throws {
    let fileURL = try temporaryFile(payload)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    try await bucket.upload(path: "file.bin", data: Data("old".utf8))
    let log = ProgressLog()

    try await bucket.update(path: "file.bin", fileURL: fileURL, progress: log.callback)

    log.expectRisesTo(Int64(payload.count))
    #expect(try await bucket.info(path: "file.bin").size == Int64(payload.count))
  }

  @Test
  func signedURLUploadReportsProgressUpToItsSize() async throws {
    let signed = try await bucket.createSignedUploadURL(path: "signed.bin")
    let log = ProgressLog()

    try await bucket.uploadToSignedURL(
      path: "signed.bin", token: signed.token, data: payload, progress: log.callback)

    log.expectRisesTo(Int64(payload.count))
  }

  // MARK: - Streamed upload bodies

  /// `payload` as 1 MiB chunks, pulled one at a time.
  private func streamed(length: HTTPBody.Length) -> HTTPBody {
    let payload = payload
    let chunks = AsyncStream { continuation in
      for start in stride(from: 0, to: payload.count, by: 1 << 20) {
        continuation.yield(ArraySlice(payload[start..<min(start + (1 << 20), payload.count)]))
      }
      continuation.finish()
    }
    return HTTPBody(chunks, length: length, iterationBehavior: .single)
  }

  @Test(arguments: [HTTPBody.Length.known(4 << 20), .unknown])
  func uploadsAStreamedBody(length: HTTPBody.Length) async throws {
    let log = ProgressLog()

    try await bucket.upload(
      path: "stream.bin", body: streamed(length: length), progress: log.callback)

    #expect(try await bucket.info(path: "stream.bin").size == Int64(payload.count))
    let completed = log.reports.value.map(\.completedBytes)
    #expect(completed == completed.sorted())
    #expect(completed.last == Int64(payload.count))
  }

  @Test
  func updatesAndSignsWithAStreamedBody() async throws {
    try await bucket.upload(path: "a.bin", data: Data("old".utf8))
    try await bucket.update(path: "a.bin", body: streamed(length: .known(4 << 20)))
    let signed = try await bucket.createSignedUploadURL(path: "b.bin")
    try await bucket.uploadToSignedURL(
      path: "b.bin", token: signed.token, body: streamed(length: .known(4 << 20)))

    #expect(try await bucket.info(path: "a.bin").size == Int64(payload.count))
    #expect(try await bucket.info(path: "b.bin").size == Int64(payload.count))
  }

  @Test
  func aKnownLengthOverTheBucketLimitIsRefused() async throws {
    let name = try await StorageIntegration.newBucket(
      "transfer-small", options: BucketOptions(isPublic: true, fileSizeLimit: .megabytes(1)))
    defer { StorageIntegration.dropBucket(name) }

    let error = await StorageIntegration.storageError {
      try await StorageIntegration.admin.from(name).upload(
        path: "big.bin", body: self.streamed(length: .known(4 << 20)))
    }

    #expect(error?.code == .entityTooLarge)
  }

  // MARK: - Data downloads

  @Test
  func downloadsARange() async throws {
    try await bucket.upload(path: "range.bin", data: payload)

    let data = try await bucket.download(
      path: "range.bin", options: DownloadOptions(range: 1000...1999)
    ).data()

    #expect(data == payload[1000...1999])
  }

  @Test
  func downloadReportsProgressUpToTheSize() async throws {
    try await bucket.upload(path: "progress.bin", data: payload)
    let log = ProgressLog()

    let data = try await bucket.download(path: "progress.bin", progress: log.callback).data()

    #expect(data == payload)
    log.expectRisesTo(Int64(payload.count))
  }

  @Test
  func downloadSendsTheCacheNonceAndHeaders() async throws {
    try await bucket.upload(path: "nonce.bin", data: payload)

    let data = try await bucket.download(
      path: "nonce.bin",
      options: DownloadOptions(cacheNonce: UUID().uuidString, headers: [.range: "bytes=0-9"])
    ).data()

    #expect(data == payload[0...9])
  }

  // MARK: - Response metadata and streaming

  @Test
  func downloadStreamsTheObjectWithItsMetadata() async throws {
    try await bucket.upload(
      path: "bytes.bin", data: payload,
      options: UploadOptions(contentType: "application/octet-stream", cacheControl: .noCache))

    let response = try await bucket.download(path: "bytes.bin")
    var received = Data()
    var chunks = 0
    for try await chunk in response.body {
      received.append(contentsOf: chunk)
      chunks += 1
    }

    #expect(received == payload)
    #if !canImport(FoundationNetworking)
      #expect(chunks > 1)
    #endif
    #expect(response.contentType == "application/octet-stream")
    #expect(response.contentLength == Int64(payload.count))
    #expect(response.cacheControl?.contains("no-cache") == true)
    #expect(response.eTag != nil)
    #expect(response.lastModified != nil)
  }

  @Test
  func downloadOfARangeReportsItsContentRange() async throws {
    try await bucket.upload(path: "bytes-range.bin", data: payload)

    let response = try await bucket.download(
      path: "bytes-range.bin", options: DownloadOptions(range: 10...19))

    #expect(response.httpResponse.status == .partialContent)
    #expect(response.contentRange == "bytes 10-19/\(payload.count)")
    #expect(response.contentLength == 10)
    #expect(try await response.data() == payload[10...19])
  }

  @Test
  func downloadOfAMissingObjectThrowsBeforeReturning() async throws {
    let error = await StorageIntegration.storageError {
      _ = try await self.bucket.download(path: "missing.bin")
    }

    #expect(error?.isNotFound == true)
  }
}
