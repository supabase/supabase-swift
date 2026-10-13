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
}
