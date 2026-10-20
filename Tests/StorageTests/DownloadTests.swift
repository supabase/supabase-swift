import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct DownloadTests {
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

    _ = try await bucket.download(
      path: "file.txt", options: DownloadOptions(range: 0...9, headers: [.range: "bytes=5-"]))

    #expect(sent.value?.headerFields[.range] == "bytes=5-")
  }

  @Test
  func reportsProgressAsTheBodyIsRead() async throws {
    let reports = LockIsolated<[TransferProgress]>([])
    let bucket = Self.makeBucket { Self.chunks(8, of: 64 << 10) }

    let response = try await bucket.download(path: "file.bin") { progress in
      reports.withValue { $0.append(progress) }
    }
    #expect(reports.value.isEmpty)
    let data = try await response.data()

    #expect(data.count == 8 << 16)
    let completed = reports.value.map(\.completedBytes)
    #expect(completed == completed.sorted())
    #expect(
      reports.value.last == TransferProgress(completedBytes: 8 << 16, totalBytes: 8 << 16))
  }

  @Test
  func aNetworkFailureMidBodyIsATransportError() async throws {
    let bucket = Self.makeBucket {
      Self.chunks(2, of: 10, length: .unknown, then: URLError(.networkConnectionLost))
    }

    let response = try await bucket.download(path: "file.txt")
    let error = await #expect(throws: StorageError.self) {
      try await response.data()
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

  @Test
  func returnsTheHeadBeforeTheBodyIsRead() async throws {
    let pulled = LockIsolated(0)
    let bucket = Self.makeBucket(
      status: .partialContent,
      headers: [
        .contentType: "text/plain",
        .contentLength: "20",
        .contentRange: "bytes 0-19/100",
        .eTag: "\"abc\"",
        .lastModified: "Tue, 13 Oct 2026 15:00:00 GMT",
        .cacheControl: "max-age=3600",
      ]
    ) {
      let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> {
        pulled.withValue { $0 += 1 }
        return pulled.value <= 2 ? ArraySlice(repeating: 1, count: 10) : nil
      }
      return HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
    }

    let response = try await bucket.download(
      path: "file.txt", options: DownloadOptions(range: 0...19))

    #expect(pulled.value == 0)
    #expect(response.httpResponse.status == .partialContent)
    #expect(response.contentType == "text/plain")
    #expect(response.contentLength == 20)
    #expect(response.contentRange == "bytes 0-19/100")
    #expect(response.eTag == "\"abc\"")
    #expect(response.lastModified == Date(timeIntervalSince1970: 1_791_903_600))
    #expect(response.cacheControl == "max-age=3600")

    let data = try await response.data()
    #expect(data.count == 20)
  }

  @Test
  func anEmptyResponseIsAnEmptyBody() async throws {
    let response = try await Self.makeBucket { nil }.download(path: "empty.txt")

    let data = try await response.data()
    #expect(data.isEmpty)
    #expect(response.lastModified == nil)
  }

  @Test
  func dataStopsAtTheCap() async throws {
    let response = try await Self.makeBucket { Self.chunks(4, of: 10, length: .unknown) }
      .download(path: "file.bin")

    let error = await #expect(throws: HTTPBodyTooLargeError.self) {
      try await response.data(upTo: 25)
    }

    #expect(error?.maxBytes == 25)
  }

  @Test
  func writeStreamsTheBodyToAFile() async throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try await Self.makeBucket { Self.chunks(8, of: 64 << 10) }
      .download(path: "file.bin")
      .write(to: fileURL)

    #expect(try Data(contentsOf: fileURL).count == 8 << 16)
  }
}
