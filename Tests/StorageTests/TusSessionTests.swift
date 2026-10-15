import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import InlineSnapshotTesting
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct TusSessionTests {
  private let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  private let uploadURL = URL(string: "http://localhost:54321/storage/v1/upload/resumable/abc")!

  private func makeSUT(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ) -> TusSession {
    TusSession(
      api: StorageAPI(
        configuration: StorageClientConfiguration(
          url: supabaseURL,
          headers: [.authorization: "Bearer test.api.key", .xClientInfo: "storage-swift/x.y.z"],
          http: .init(
            transport: ClosureTransport { request, body in
              guard var urlRequest = URLRequest(httpRequest: request) else {
                throw URLError(.badURL)
              }
              if let body { urlRequest.httpBody = try await Data(collecting: body, upTo: .max) }
              let (data, response) = try await fetch(urlRequest)
              guard let head = (response as? HTTPURLResponse)?.httpResponse else {
                throw URLError(.badServerResponse)
              }
              return (head, data.isEmpty ? nil : HTTPBody(data))
            }))))
  }

  private func response(
    _ status: Int, headers: [String: String] = [:], body: String = ""
  ) -> (Data, URLResponse) {
    (
      Data(body.utf8),
      HTTPURLResponse(
        url: supabaseURL, statusCode: status, httpVersion: nil, headerFields: headers)!
    )
  }

  private var options: UploadOptions {
    UploadOptions(
      contentType: "video/mp4", cacheControl: .maxAge(.seconds(3600)), upsert: true,
      metadata: ["key": "value"])
  }

  @Test
  func createSendsTusHeadersAndReadsTheLocation() async throws {
    let sut = makeSUT { request in
      assertInlineSnapshot(of: request, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer test.api.key" \
        	--header "Tus-Resumable: 1.0.0" \
        	--header "Upload-Length: 20" \
        	--header "Upload-Metadata: bucketName YnVja2V0,objectName Zm9sZGVyL3ZpZGVvLm1wNA==,contentType dmlkZW8vbXA0,cacheControl MzYwMA==,metadata eyJrZXkiOiJ2YWx1ZSJ9" \
        	--header "X-Client-Info: storage-swift/x.y.z" \
        	--header "x-upsert: true" \
        	"http://localhost:54321/storage/v1/upload/resumable"
        """#
      }
      return self.response(
        201,
        headers: [
          "Location": "/storage/v1/upload/resumable/abc",
          "Upload-Offset": "0",
          "Upload-Expires": "Tue, 13 Oct 2026 15:00:00 GMT",
        ])
    }

    let created = try await sut.create(
      bucket: "bucket", key: try ObjectKey("folder/video.mp4"), length: 20, options: options)

    #expect(created.uploadURL == uploadURL)
    #expect(created.offset == 0)
    #expect(created.expiresAt == Date(timeIntervalSince1970: 1_791_903_600))
  }

  @Test
  func createWithoutUploadOffsetStartsAtZero() async throws {
    let sut = makeSUT { _ in
      self.response(201, headers: ["Location": "/storage/v1/upload/resumable/abc"])
    }

    let created = try await sut.create(
      bucket: "bucket", key: try ObjectKey("a"), length: 20, options: options)

    #expect(created.offset == 0)
  }

  @Test
  func createWithTheFirstChunkSendsItAsAnOffsetStream() async throws {
    let sut = makeSUT { request in
      #expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/offset+octet-stream")
      #expect(request.httpBody == Data(repeating: 1, count: 6))
      return self.response(
        201, headers: ["Location": "/storage/v1/upload/resumable/abc", "Upload-Offset": "6"])
    }

    let created = try await sut.create(
      bucket: "bucket", key: try ObjectKey("video.mp4"), length: 20, options: options,
      firstChunk: Data(repeating: 1, count: 6))

    #expect(created.offset == 6)
    #expect(created.expiresAt == nil)
  }

  @Test
  func createPassesServerErrorsThrough() async throws {
    let sut = makeSUT { _ in
      self.response(413, headers: ["Content-Type": "text/plain"], body: "Payload too large")
    }

    let error = await #expect(throws: StorageError.self) {
      try await sut.create(
        bucket: "bucket", key: try ObjectKey("video.mp4"), length: 20, options: options)
    }
    #expect(error?.code == StorageError.Code.entityTooLarge)
  }

  @Test
  func offsetSendsHeadAndReadsUploadOffset() async throws {
    let sut = makeSUT { request in
      #expect(request.httpMethod == "HEAD")
      #expect(request.url == self.uploadURL)
      #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
      return self.response(200, headers: ["Upload-Offset": "12"])
    }

    #expect(try await sut.offset(of: uploadURL) == 12)
  }

  @Test
  func offsetOfAGoneUploadThrowsUploadGone() async throws {
    let sut = makeSUT { _ in
      self.response(404, headers: ["Content-Type": "text/plain"], body: "Not found")
    }

    await #expect(throws: TusSession.Failure.self) { try await sut.offset(of: uploadURL) }
  }

  @Test
  func appendSendsPatchAndReadsOffsetAndCompletion() async throws {
    let sut = makeSUT { request in
      assertInlineSnapshot(of: request, as: .curl) {
        #"""
        curl \
        	--request PATCH \
        	--header "Authorization: Bearer test.api.key" \
        	--header "Content-Type: application/offset+octet-stream" \
        	--header "Tus-Resumable: 1.0.0" \
        	--header "Upload-Offset: 12" \
        	--header "X-Client-Info: storage-swift/x.y.z" \
        	--data "chunk" \
        	"http://localhost:54321/storage/v1/upload/resumable/abc"
        """#
      }
      return self.response(
        204, headers: ["Upload-Offset": "17", "Tus-Complete": "1"], body: #"{"Key":"bucket/a"}"#)
    }

    let appended = try await sut.append(Data("chunk".utf8), at: 12, to: uploadURL)

    #expect(
      appended
        == TusSession.Appended(offset: 17, complete: true, body: Data(#"{"Key":"bucket/a"}"#.utf8)))
  }

  @Test
  func appendWithoutCompletionReportsIncomplete() async throws {
    let sut = makeSUT { _ in self.response(204, headers: ["Upload-Offset": "17"]) }

    let appended = try await sut.append(Data("chunk".utf8), at: 12, to: uploadURL)

    #expect(appended == TusSession.Appended(offset: 17, complete: false, body: Data()))
  }

  @Test
  func appendOffsetConflictThrowsOffsetConflict() async throws {
    let sut = makeSUT { _ in
      self.response(409, headers: ["Content-Type": "text/plain"], body: "Offset conflict")
    }

    let error = await #expect(throws: TusSession.Failure.self) {
      try await sut.append(Data("chunk".utf8), at: 12, to: uploadURL)
    }
    guard case .offsetConflict(let storageError)? = error else {
      Issue.record("Expected offsetConflict, got \(String(describing: error))")
      return
    }
    #expect(storageError.serverStatusCode == 409)
  }

  @Test
  func appendToAGoneUploadThrowsUploadGone() async throws {
    let sut = makeSUT { _ in
      self.response(410, headers: ["Content-Type": "text/plain"], body: "Gone")
    }

    let error = await #expect(throws: TusSession.Failure.self) {
      try await sut.append(Data("chunk".utf8), at: 12, to: uploadURL)
    }
    guard case .uploadGone? = error else {
      Issue.record("Expected uploadGone, got \(String(describing: error))")
      return
    }
  }

  @Test
  func terminateSendsDeleteAndIgnoresFailure() async throws {
    let sent = LockIsolated<URLRequest?>(nil)
    let sut = makeSUT { request in
      sent.setValue(request)
      return self.response(500)
    }

    await sut.terminate(uploadURL)

    #expect(sent.value?.httpMethod == "DELETE")
    #expect(sent.value?.url == uploadURL)
    #expect(sent.value?.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
  }
}
