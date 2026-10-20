import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct TransferProgressTests {
  @Test
  func fractionCompleted() {
    #expect(TransferProgress(completedBytes: 25, totalBytes: 100).fractionCompleted == 0.25)
    #expect(TransferProgress(completedBytes: 25, totalBytes: nil).fractionCompleted == nil)
    #expect(TransferProgress(completedBytes: 0, totalBytes: 0).fractionCompleted == nil)
  }

  private func makeBucket() -> StorageBucket {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { _, body in
            let body = try #require(body)
            let hook = try #require(body.onUploadProgress)
            guard case .known(let total) = body.length else { throw URLError(.unknown) }
            for sent in stride(from: Int64(0), through: total, by: 4096) { hook(sent) }
            hook(total)
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(#"{"Key":"bucket/file.bin"}"#.utf8))
            )
          }))
    )
    .from("bucket")
  }

  @Test
  func uploadReportsUpToTheBodySize() async throws {
    let reports = LockIsolated<[TransferProgress]>([])
    let data = Data(count: 100_000)

    try await makeBucket().upload(path: "file.bin", data: data) { progress in
      reports.withValue { $0.append(progress) }
    }

    let completed = reports.value.map(\.completedBytes)
    #expect(completed == completed.sorted())
    #expect(reports.value.last == TransferProgress(completedBytes: 100_000, totalBytes: 100_000))
  }

  @Test
  func signedURLUploadFromAFileReportsItsSize() async throws {
    let reports = LockIsolated<[TransferProgress]>([])
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data(count: 50_000).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await makeBucket().uploadToSignedURL(
      path: "file.bin", token: "t", fileURL: fileURL
    ) { progress in
      reports.withValue { $0.append(progress) }
    }

    #expect(reports.value.last == TransferProgress(completedBytes: 50_000, totalBytes: 50_000))
  }
}
