import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct DownloadTests {
  /// A stream of `count` chunks of `size` bytes that throws `error` after the last one, if given.
  static func chunks(
    _ count: Int, of size: Int, length: HTTPBody.Length? = nil, then error: (any Error)? = nil
  ) -> HTTPBody {
    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
      for index in 0..<count {
        continuation.yield(ArraySlice(repeating: UInt8(index), count: size))
      }
      continuation.finish(throwing: error)
    }
    return HTTPBody(
      chunks, length: length ?? .known(Int64(count * size)), iterationBehavior: .single)
  }

  static func makeBucket(
    sent: LockIsolated<HTTPRequest?> = .init(nil),
    status: HTTPResponse.Status = .ok,
    headers: HTTPFields = [:],
    body: @escaping @Sendable () -> HTTPBody?
  ) -> StorageBucket {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, _ in
            sent.setValue(request)
            return (HTTPResponse(status: status, headerFields: headers), body())
          }))
    )
    .from("bucket")
  }

  @Test
  func sendsRangeVersionNonceAndHeaders() async throws {
    let sent = LockIsolated<HTTPRequest?>(nil)
    let bucket = Self.makeBucket(sent: sent) { HTTPBody(Data("abc".utf8)) }

    _ = try await bucket.download(
      path: "file.txt",
      transform: ImageTransform(width: 10),
      options: DownloadOptions(
        range: 0...1023, versionId: "v1", cacheNonce: "n",
        headers: [.init("x-custom")!: "1", .ifNoneMatch: "\"etag\""]))

    let request = try #require(sent.value)
    #expect(
      request.path
        == "/storage/v1/render/image/authenticated/bucket/file.txt?width=10&versionId=v1&cacheNonce=n"
    )
    #expect(request.headerFields[.range] == "bytes=0-1023")
    #expect(request.headerFields[.init("x-custom")!] == "1")
    #expect(request.headerFields[.ifNoneMatch] == "\"etag\"")
  }

  @Test
  func headersOverrideTheRange() async throws {
    let sent = LockIsolated<HTTPRequest?>(nil)
    let bucket = Self.makeBucket(sent: sent) { nil }

    let data = try await bucket.download(
      path: "file.txt", options: DownloadOptions(range: 0...9, headers: [.range: "bytes=5-"]))

    #expect(sent.value?.headerFields[.range] == "bytes=5-")
    #expect(data.isEmpty)
  }

  @Test
  func reportsProgressUpToTheContentLength() async throws {
    let reports = LockIsolated<[TransferProgress]>([])
    let bucket = Self.makeBucket { Self.chunks(8, of: 64 << 10) }

    let data = try await bucket.download(path: "file.bin") { progress in
      reports.withValue { $0.append(progress) }
    }

    #expect(data.count == 8 << 16)
    let completed = reports.value.map(\.completedBytes)
    #expect(completed == completed.sorted())
    #expect(
      reports.value.last == TransferProgress(completedBytes: 8 << 16, totalBytes: 8 << 16))
  }

  @Test
  func aNetworkFailureMidBodyIsATransportError() async throws {
    let bucket = Self.makeBucket {
      Self.chunks(2, of: 10, then: URLError(.networkConnectionLost))
    }

    let error = await #expect(throws: StorageError.self) {
      try await bucket.download(path: "file.txt")
    }

    #expect(error?.kind == .transport)
    #expect((error?.underlyingError as? URLError)?.code == .networkConnectionLost)
  }

  @Test
  func aServerErrorIsDecoded() async throws {
    let bucket = Self.makeBucket(status: .notFound, headers: [.contentType: "application/json"]) {
      HTTPBody(Data(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#.utf8))
    }

    let error = await #expect(throws: StorageError.self) {
      try await bucket.download(path: "missing.txt")
    }

    #expect(error?.kind == .server)
    #expect(error?.message == "Object not found")
  }
}
