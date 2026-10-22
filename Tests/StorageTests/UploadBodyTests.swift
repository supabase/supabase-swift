import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct UploadBodyTests {
  private struct Sent {
    var request: HTTPRequest
    var body: Data
  }

  private func makeBucket(sent: LockIsolated<Sent?>) -> StorageBucket {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, body in
            let data = try await Data(collecting: #require(body), upTo: .max)
            sent.setValue(Sent(request: request, body: data))
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(#"{"Key":"bucket/clip.mov"}"#.utf8))
            )
          }))
    )
    .from("bucket")
  }

  private func chunks(_ count: Int, of size: Int) -> HTTPBody {
    let chunks = AsyncStream { continuation in
      for index in 0..<count {
        continuation.yield(ArraySlice(repeating: UInt8(index), count: size))
      }
      continuation.finish()
    }
    return HTTPBody(chunks, length: .known(Int64(count * size)), iterationBehavior: .single)
  }

  @Test
  func uploadStreamsTheBodyAndReportsProgressAsItIsPulled() async throws {
    let sent = LockIsolated<Sent?>(nil)
    let reports = LockIsolated<[TransferProgress]>([])

    let object = try await makeBucket(sent: sent).upload(
      path: "clip.mov", body: chunks(8, of: 64 << 10)
    ) { progress in
      reports.withValue { $0.append(progress) }
    }

    let request = try #require(sent.value?.request)
    #expect(request.method == .post)
    #expect(request.path == "/storage/v1/object/bucket/clip.mov")
    #expect(request.headerFields[.contentType] == mimeType(forPathExtension: "mov"))
    #expect(request.headerFields[.init("x-upsert")!] == "false")
    #expect(sent.value?.body.count == 8 * (64 << 10))
    #expect(object.fullPath == "bucket/clip.mov")
    #expect(
      reports.value.last == TransferProgress(completedBytes: 8 << 16, totalBytes: 8 << 16))
  }

  @Test
  func updateSendsPut() async throws {
    let sent = LockIsolated<Sent?>(nil)

    try await makeBucket(sent: sent).update(path: "clip.mov", body: chunks(1, of: 10))

    #expect(sent.value?.request.method == .put)
    #expect(sent.value?.request.path == "/storage/v1/object/bucket/clip.mov")
    #expect(sent.value?.body.count == 10)
  }

  @Test
  func uploadToSignedURLSendsTheToken() async throws {
    let sent = LockIsolated<Sent?>(nil)

    let object = try await makeBucket(sent: sent).uploadToSignedURL(
      path: "clip.mov", token: "abc", body: chunks(1, of: 10),
      options: UploadOptions(contentType: "application/octet-stream"))

    #expect(sent.value?.request.method == .put)
    #expect(sent.value?.request.path == "/storage/v1/object/upload/sign/bucket/clip.mov?token=abc")
    #expect(sent.value?.request.headerFields[.contentType] == "application/octet-stream")
    #expect(object.id == nil)
  }

  @Test
  func fileUploadTakesItsContentTypeFromTheFile() async throws {
    let sent = LockIsolated<Sent?>(nil)
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).png")
    try Data(count: 10).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await makeBucket(sent: sent).upload(path: "avatar", fileURL: fileURL)

    #expect(sent.value?.request.headerFields[.contentType] == mimeType(forPathExtension: "png"))
  }
}
