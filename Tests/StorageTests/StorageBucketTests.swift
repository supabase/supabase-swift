import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageBucketTests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let transport = RecordingTransport()

  private func makeSUT() throws -> StorageClient {
    try StorageClient(
      configuration: StorageClient.Configuration(
        url: url,
        headers: [
          .init("apikey")!:
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        http: .init(transport: transport))
    )
  }

  private func makeRequestCapturingSUT(request captured: LockIsolated<HTTPRequest?>)
    throws -> StorageClient
  {
    try StorageClient(
      configuration: StorageClient.Configuration(
        url: url,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, _ in
            guard let urlRequest = URLRequest(httpRequest: request) else {
              throw URLError(.badURL)
            }
            captured.setValue(request)
            let response = HTTPURLResponse(
              url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            guard let head = response.httpResponse else { throw URLError(.badServerResponse) }
            return (
              head,
              HTTPBody(Data(#"{"Key":"bucket/\#(urlRequest.url!.lastPathComponent)"}"#.utf8))
            )
          }))
    )
  }

  private func makeBodyCapturingSUT(body captured: LockIsolated<Data?>, response: String)
    throws -> StorageClient
  {
    try StorageClient(
      configuration: StorageClient.Configuration(
        url: url,
        headers: [:],
        http: .init(
          transport: ClosureTransport { _, body in
            if let body {
              let data = try await Data(collecting: body, upTo: .max)
              captured.setValue(data)
            }
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(response.utf8))
            )
          }))
    )
  }

  private func makeFailingSUT(_ failure: @escaping @Sendable () throws -> Never)
    throws -> StorageClient
  {
    try StorageClient(
      configuration: StorageClient.Configuration(
        url: url,
        headers: [:],
        http: .init(transport: ClosureTransport { _, _ in try failure() })
      )
    )
  }

  @Test
  func transportFailureIsWrapped() async throws {
    let storage = try makeFailingSUT { throw URLError(.timedOut) }

    do {
      _ = try await storage.from("bucket").list()
      Issue.record("Expected failure")
    } catch let error as StorageError {
      #expect(error.kind == .transport)
      #expect(error.response == nil)
      #expect((error.underlyingError as? URLError)?.code == .timedOut)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func cancellationIsNotWrapped() async throws {
    let storage = try makeFailingSUT { throw CancellationError() }

    await #expect(throws: CancellationError.self) {
      _ = try await storage.from("bucket").list()
    }
  }

  @Test
  func cancelledURLErrorWithoutTaskCancellationIsWrapped() async throws {
    let storage = try makeFailingSUT { throw URLError(.cancelled) }

    do {
      _ = try await storage.from("bucket").list()
      Issue.record("Expected failure")
    } catch let error as StorageError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .cancelled)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func cancellingTheTaskThrowsCancellationError() async throws {
    let storage = try makeSUT()
    let inFlight = Gate()

    // URLSession fails a cancelled task with `URLError(.cancelled)`, not `CancellationError`.
    transport.stub(.post, url.appendingPathComponent("object/list/bucket")) { _, _ in
      await inFlight.pass()
      throw URLError(.cancelled)
    }

    let task = Task { try await storage.from("bucket").list() }
    await inFlight.arrivals(1)
    task.cancel()

    do {
      _ = try await task.value
      Issue.record("Expected failure")
    } catch is CancellationError {
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func customFetchErrorIsNotWrapped() async throws {
    struct FetchError: Error {}
    let storage = try makeFailingSUT { throw FetchError() }

    await #expect(throws: FetchError.self) {
      _ = try await storage.from("bucket").list()
    }
  }

  @Test
  func undecodableSuccessBodyIsWrapped() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("not json".utf8)
    )

    do {
      _ = try await storage.from("bucket").list()
      Issue.record("Expected failure")
    } catch let error as StorageError {
      #expect(error.kind == .decoding)
      #expect(error.underlyingError is DecodingError)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func configuration() throws {
    let storage = try makeSUT()
    #expect(storage.from("bucket").configuration.url == url)
  }

  @Test
  func listFiles() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data(
        """
        [
          {
            "name": "test.txt",
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "updatedAt": "2024-01-01T00:00:00Z",
            "createdAt": "2024-01-01T00:00:00Z",
            "lastAccessedAt": "2024-01-01T00:00:00Z",
            "metadata": {}
          }
        ]
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 83" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":100,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    let result = try await storage.from("bucket").list(path: "folder")
    #expect(result.count == 1)
    #expect(result[0].name == "test.txt")
  }

  @Test
  func listFilesWithPartialSortByColumn() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 89" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":100,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"updated_at\",\"order\":\"asc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(sortBy: .updatedAt)
    )
  }

  @Test
  func listFilesWithPartialSortByOrder() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 84" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":100,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"desc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(order: .descending)
    )
  }

  @Test
  func listFilesWithFullSortByOverride() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 90" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":100,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"updated_at\",\"order\":\"desc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(sortBy: .updatedAt, order: .descending)
    )
  }

  @Test
  func listFilesPreservesDefaultLimitWhenOnlyOffsetProvided() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 84" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":100,\"offset\":10,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(offset: 10, sortBy: .name, order: .ascending)
    )
  }

  @Test
  func listFilesPreservesDefaultOffsetWhenOnlyLimitProvided() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 82" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":50,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(limit: 50, sortBy: .name, order: .ascending)
    )
  }

  @Test
  func listFilesWithExplicitZeroLimitIsNotTreatedAsMissing() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/list/bucket"),
      data: Data("[]".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 81" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"limit\":0,\"offset\":5,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}" \
      	"http://localhost:54321/storage/v1/object/list/bucket"
      """#
    }

    _ = try await storage.from("bucket").list(
      path: "folder",
      options: ListOptions(
        limit: 0, offset: 5, sortBy: .name, order: .ascending)
    )
  }

  @Test
  func listFilesSendsSearchExactMatchAndVersionFilters() async throws {
    let body = LockIsolated<Data?>(nil)
    let storage = try makeBodyCapturingSUT(body: body, response: "[]")

    _ = try await storage.from("bucket").list(
      path: "folder/a.txt",
      options: ListOptions(
        sortBy: .lastAccessedAt, search: "a", exactMatch: true, versions: .include,
        deleteMarkers: .only)
    )

    #expect(
      String(decoding: try #require(body.value), as: UTF8.self)
        == #"{"deleteMarkers":"only","exactMatch":true,"limit":100,"noncurrentVersions":"include","offset":0,"prefix":"folder\/a.txt","search":"a","sortBy":{"column":"last_accessed_at","order":"asc"}}"#
    )
  }

  @Test
  func move() async throws {
    let storage = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("object/move")) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 82" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationKey\":\"new\/path.txt\",\"sourceKey\":\"old\/path.txt\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }

    try await storage.from("bucket").move(
      from: "old/path.txt",
      to: "new/path.txt"
    )
  }

  @Test
  func copy() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/copy"),
      data: Data(
        """
        {
          "Key": "object/dest/file.txt"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 86" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationKey\":\"dest\/file.txt\",\"sourceKey\":\"source\/file.txt\"}" \
      	"http://localhost:54321/storage/v1/object/copy"
      """#
    }

    let key = try await storage.from("bucket").copy(
      from: "source/file.txt",
      to: "dest/file.txt"
    )

    #expect(key.fullPath == "object/dest/file.txt")
    #expect(key.path == "dest/file.txt")
  }

  @Test
  func createSignedURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
      """#
    }

    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: .seconds(3600)
    )
    #expect(
      url.absoluteString == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  @Test
  func createSignedURL_emptyTransformIsNotSent() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "signedURL": "object/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
      """#
    }

    _ = try await storage.from("bucket").createSignedURL(
      path: "file.txt", expiresIn: .seconds(3600),
      options: SignedURLOptions(transform: ImageTransform()))
  }

  @Test
  func createSignedURL_malformedSignedURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "signedURL": "http://[::1"
        }
        """.utf8
      )
    )

    do {
      _ = try await storage.from("bucket").createSignedURL(
        path: "file.txt",
        expiresIn: .seconds(3600)
      )
      Issue.record("expected createSignedURL to throw")
    } catch let error as StorageError {
      #expect(error.kind == .decoding)
      #expect(error.response == nil)
    }
  }

  @Test
  func createSignedURL_download() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
      """#
    }

    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt", expiresIn: .seconds(3600),
      options: SignedURLOptions(download: .withOriginalName))
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
  }

  @Test(arguments: [Duration.zero, .milliseconds(999), .seconds(-5)])
  func createSignedURLRejectsLessThanOneSecondBeforeSending(expiresIn: Duration) async throws {
    let storage = try makeFailingSUT {
      Issue.record("A request was sent"); throw URLError(.badURL)
    }

    await #expect {
      try await storage.from("bucket").createSignedURL(path: "file.txt", expiresIn: expiresIn)
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
    await #expect {
      try await storage.from("bucket").createSignedURLs(paths: ["file.txt"], expiresIn: expiresIn)
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
  }

  @Test
  func createSignedURLs() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket"),
      data: Data(
        """
        [
          {
            "path": "file.txt",
            "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
          },
          {
            "path": "file2.txt",
            "signedURL": "object/upload/sign/bucket/file2.txt?token=abc.def.ghi"
          }
        ]
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600,\"paths\":[\"file.txt\",\"file2.txt\"]}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket"
      """#
    }

    let paths = ["file.txt", "file2.txt"]
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: paths,
      expiresIn: .seconds(3600)
    )
    #expect(results.count == 2)
    guard case .success(let path0, let url0) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(path0 == "file.txt")
    #expect(
      url0.absoluteString == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
    guard case .success(let path1, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(path1 == "file2.txt")
    #expect(
      url1.absoluteString == "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi")
  }

  @Test
  func createSignedURLs_download() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket"),
      data: Data(
        """
        [
          {
            "path": "file.txt",
            "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
          },
          {
            "path": "file2.txt",
            "signedURL": "object/upload/sign/bucket/file2.txt?token=abc.def.ghi"
          }
        ]
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600,\"paths\":[\"file.txt\",\"file2.txt\"]}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket"
      """#
    }

    let paths = ["file.txt", "file2.txt"]
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: paths, expiresIn: .seconds(3600),
      options: SignedURLsOptions(download: .withOriginalName))
    #expect(results.count == 2)
    guard case .success(_, let url0) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      url0.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
    guard case .success(_, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(
      url1.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi&download=")
  }

  @Test
  func createSignedURLs_withNullSignedURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket"),
      data: Data(
        """
        [
          {
            "path": "file.txt",
            "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
          },
          {
            "path": "missing.txt",
            "signedURL": null,
            "error": "Either the object does not exist or you do not have access to it"
          }
        ]
        """.utf8
      )
    )

    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: ["file.txt", "missing.txt"],
      expiresIn: .seconds(3600)
    )
    #expect(results.count == 2)
    guard case .success(let path0, _) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(path0 == "file.txt")
    guard case .failure(let path1, let error1) = results[1] else {
      Issue.record("Expected failure for missing.txt")
      return
    }
    #expect(path1 == "missing.txt")
    #expect(error1 == "Either the object does not exist or you do not have access to it")
  }

  @Test
  func remove() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("object/bucket"),
      status: .noContent,
      data: Data(
        """
        [
          {
            "name": "file1.txt",
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "updatedAt": "2024-01-01T00:00:00Z",
            "createdAt": "2024-01-01T00:00:00Z",
            "lastAccessedAt": "2024-01-01T00:00:00Z",
            "metadata": {}
          },
          {
            "name": "file2.txt",
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E00",
            "updatedAt": "2024-01-01T00:00:00Z",
            "createdAt": "2024-01-01T00:00:00Z",
            "lastAccessedAt": "2024-01-01T00:00:00Z",
            "metadata": {}
          }
        ]
        """.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "Content-Length: 38" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"prefixes\":[\"file1.txt\",\"file2.txt\"]}" \
      	"http://localhost:54321/storage/v1/object/bucket"
      """#
    }

    let objects = try await storage.from("bucket").remove(
      paths: ["file1.txt", "file2.txt"]
    )

    #expect(objects[0].name == "file1.txt")
    #expect(objects[1].name == "file2.txt")
  }

  @Test
  func nonSuccessStatusCode() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/move"),
      status: .badRequest,
      data: Data(
        """
        {
          "message":"Error"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 73" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      Issue.record()
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.message == "Error")
      #expect(error.serverError?.message == "Error")
      #expect(error.response?.status == 400)
    }
  }

  @Test
  func nonSuccessStatusCodeWithNonJSONResponse() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/move"),
      status: .preconditionFailed,
      data: Data("error".utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 73" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      Issue.record()
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.serverError == nil)
      #expect(error.response?.body == Data("error".utf8))
      #expect(error.response?.status == 412)
    }
  }

  @Test
  func nonSuccessStatusCodeExposesTheServerErrorCode() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/missing.txt"),
      status: .badRequest,
      data: Data(
        """
        {
          "statusCode":"404",
          "error":"not_found",
          "message":"Object not found",
          "code":"NoSuchKey"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/missing.txt"
      """#
    }

    do {
      _ = try await storage.from("bucket").download(path: "missing.txt")
      Issue.record()
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.code == .noSuchKey)
      #expect(error.serverError?.error == "not_found")
      #expect(error.response?.status == 400)
    }
  }

  @Test
  func updateFromData() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data(
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "bucket/file.txt"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 11" \
      	--header "Content-Type: text/plain" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-metadata: eyJtb2RlIjoidGVzdCJ9" \
      	--data "hello world" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .update(
        path: "file.txt",
        data: Data("hello world".utf8),
        options: UploadOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test
  func uploadReturnsCleanedPath() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/bucket/folder/file.txt"),
      data: Data(
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "bucket/folder/file.txt"
        }
        """.utf8
      )
    )

    let response = try await storage.from("bucket")
      .upload(
        path: "/folder//file.txt",
        data: Data("hello world!".utf8),
        options: UploadOptions(contentType: "text/plain")
      )

    #expect(response.path == "folder/file.txt")
    #expect(response.fullPath == "bucket/folder/file.txt")
  }

  @Test
  func uploadFromURL_honorsContentType() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data(
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "bucket/file.txt"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 13" \
      	--header "Content-Type: image/png" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-upsert: false" \
      	--data "hello world!
      " \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .upload(
        path: "file.txt",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: UploadOptions(contentType: "image/png")
      )

    #expect(response.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test
  func updateFromURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data(
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "bucket/file.txt"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 13" \
      	--header "Content-Type: text/plain" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-metadata: eyJtb2RlIjoidGVzdCJ9" \
      	--data "hello world!
      " \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .update(
        path: "file.txt",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: UploadOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test
  func download() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data("hello world".utf8)
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .download(path: "file.txt")

    #expect(try await response.data() == Data("hello world".utf8))
  }

  @Test
  func download_versionId() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data("hello world".utf8)
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt?versionId=v1"
      """#
    }

    let response = try await storage.from("bucket")
      .download(path: "file.txt", options: DownloadOptions(versionID: "v1"))

    #expect(try await response.data() == Data("hello world".utf8))
  }

  @Test
  func download_withEmptyImageTransform() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data("hello world".utf8)
    )

    let response = try await storage.from("bucket")
      .download(path: "file.txt", options: DownloadOptions(transform: ImageTransform()))

    #expect(try await response.data() == Data("hello world".utf8))
  }

  @Test
  func getPublicURL_withEmptyImageTransform() throws {
    let storage = try makeSUT()

    let publicURL = try storage.from("bucket")
      .publicURL(path: "image.png", options: PublicURLOptions(transform: ImageTransform()))

    #expect(
      publicURL.absoluteString.contains("/object/public/"),
      "Empty transform should use /object/public/ path, got: \(publicURL.absoluteString)"
    )
    #expect(
      !publicURL.absoluteString.contains("/render/image/"),
      "Empty transform should not use /render/image/ path, got: \(publicURL.absoluteString)"
    )
  }

  @Test
  func getPublicURL_withActualImageTransform() throws {
    let storage = try makeSUT()

    let publicURL = try storage.from("bucket")
      .publicURL(
        path: "image.png", options: PublicURLOptions(transform: ImageTransform(width: 200)))

    #expect(
      publicURL.absoluteString.contains("/render/image/"),
      "Non-empty transform should use /render/image/ path, got: \(publicURL.absoluteString)"
    )
  }

  @Test
  func getPublicURLStripsLeadingSlash() throws {
    let storage = try makeSUT()

    let publicURL = try storage.from("bucket")
      .publicURL(path: "/folder/image.png")

    #expect(
      publicURL.absoluteString
        == "http://localhost:54321/storage/v1/object/public/bucket/folder/image.png"
    )
  }

  @Test
  func downloadStripsLeadingSlash() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data("hello world".utf8)
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .download(path: "/file.txt")

    #expect(try await response.data() == Data("hello world".utf8))
  }

  @Test
  func getPublicURLCollapsesRepeatedAndTrailingSlashes() throws {
    let storage = try makeSUT()

    let publicURL = try storage.from("bucket")
      .publicURL(path: "folder//image.png/")

    #expect(
      publicURL.absoluteString
        == "http://localhost:54321/storage/v1/object/public/bucket/folder/image.png"
    )
  }

  @Test
  func downloadCollapsesRepeatedAndTrailingSlashes() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/folder/file.txt"),
      data: Data("hello world".utf8)
    )

    let response = try await storage.from("bucket")
      .download(path: "folder//file.txt/")

    #expect(try await response.data() == Data("hello world".utf8))
  }

  @Test
  func moveCleansPaths() async throws {
    struct Sent: Decodable {
      let sourceKey: String
      let destinationKey: String
    }
    let body = LockIsolated(Data?.none)
    let storage = try makeBodyCapturingSUT(body: body, response: "{}")

    try await storage.from("bucket").move(from: "/folder/a.png", to: "folder//b.png/")

    let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
    #expect(sent.sourceKey == "folder/a.png")
    #expect(sent.destinationKey == "folder/b.png")
  }

  @Test
  func copyCleansPaths() async throws {
    struct Sent: Decodable {
      let sourceKey: String
      let destinationKey: String
    }
    let body = LockIsolated(Data?.none)
    let storage = try makeBodyCapturingSUT(
      body: body, response: #"{"Key":"bucket/folder/b.png"}"#)

    try await storage.from("bucket").copy(from: "/folder/a.png", to: "folder//b.png/")

    let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
    #expect(sent.sourceKey == "folder/a.png")
    #expect(sent.destinationKey == "folder/b.png")
  }

  @Test
  func removeCleansPaths() async throws {
    struct Sent: Decodable {
      let prefixes: [String]
    }
    let body = LockIsolated(Data?.none)
    let storage = try makeBodyCapturingSUT(body: body, response: "[]")

    try await storage.from("bucket").remove(paths: ["/folder//a.png", "b.png/"])

    let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
    #expect(sent.prefixes == ["folder/a.png", "b.png"])
  }

  @Test
  func createSignedURLsCleansPaths() async throws {
    struct Sent: Decodable {
      let paths: [String]
    }
    let body = LockIsolated(Data?.none)
    let storage = try makeBodyCapturingSUT(body: body, response: "[]")

    _ = try await storage.from("bucket")
      .createSignedURLs(paths: ["/folder//a.png", "b.png/"], expiresIn: .seconds(60))

    let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
    #expect(sent.paths == ["folder/a.png", "b.png"])
  }

  @Test
  func listCleansPath() async throws {
    struct Sent: Decodable {
      let prefix: String
    }
    let body = LockIsolated(Data?.none)
    let storage = try makeBodyCapturingSUT(body: body, response: "[]")

    _ = try await storage.from("bucket").list(path: "/folder//nested/")

    let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
    #expect(sent.prefix == "folder/nested")
  }

  @Test
  func download_withOptions() async throws {
    let storage = try makeSUT()

    let imageData = try! Data(
      contentsOf: Bundle.module.url(forResource: "sadcat", withExtension: "jpg")!)

    transport.stub(
      .get,
      url.appendingPathComponent("render/image/authenticated/bucket/sadcat.txt"),
      data: imageData
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/render/image/authenticated/bucket/sadcat.txt?resize=cover"
      """#
    }

    let response = try await storage.from("bucket")
      .download(
        path: "sadcat.txt", options: DownloadOptions(transform: ImageTransform(resize: .cover)))

    #expect(try await response.data() == imageData)
  }

  @Test
  func info() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/info/bucket/file.txt"),
      data: Data(
        """
        {
          "name": "file.txt",
          "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "version": "2"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/info/bucket/file.txt"
      """#
    }

    let info = try await storage.from("bucket").info(path: "file.txt")

    #expect(info.name == "file.txt")
  }

  @Test
  func exists() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/info/bucket/file.txt"),
      data: Data(
        #"{"id":"b5a2d6ea-7c5e-4d3a-9b3e-1f2e3d4c5b6a","version":"v1","name":"file.txt"}"#.utf8)
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/info/bucket/file.txt"
      """#
    }

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(exists)
  }

  @Test
  func existsIsFalseForNoSuchKey() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/info/bucket/file.txt"),
      status: .badRequest,
      data: Data(
        #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#
          .utf8)
    )

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test
  func existsIsFalseForABody404WithoutACode() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/info/bucket/file.txt"),
      status: .badRequest,
      data: Data(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#.utf8)
    )

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test(arguments: [
    ("NoSuchBucket", "404", StorageError.Code.noSuchBucket), ("InvalidJWT", "400", .invalidJWT),
  ])
  func existsRethrowsOtherServerErrors(raw: String, status: String, code: StorageError.Code)
    async throws
  {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/info/bucket/file.txt"),
      status: .badRequest,
      data: Data(
        #"{"statusCode":"\#(status)","error":"\#(raw)","message":"\#(raw)","code":"\#(raw)"}"#
          .utf8)
    )

    await #expect {
      try await storage.from("bucket").exists(path: "file.txt")
    } throws: { error in
      (error as? StorageError)?.code == code
    }
  }

  @Test
  func purgeCache() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("cdn/bucket/folder/file.txt"),
      data: Data(#"{"message":"success"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/cdn/bucket/folder/file.txt"
      """#
    }

    try await storage.from("bucket").purgeCache(path: "folder/file.txt")
  }

  @Test
  func purgeCacheTransformationsOnly() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("cdn/bucket/folder/file.txt"),
      data: Data(#"{"message":"success"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/cdn/bucket/folder/file.txt?transformations=true"
      """#
    }

    try await storage.from("bucket").purgeCache(
      path: "folder/file.txt", transformationsOnly: true)
  }

  @Test
  func purgeCachePercentEncodesThePath() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("cdn/bucket/folder/my file.png"),
      data: Data(#"{"message":"success"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/cdn/bucket/folder/my%20file.png"
      """#
    }

    try await storage.from("bucket").purgeCache(path: "folder/my file.png")
  }

  @Test
  func createSignedUploadURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .createSignedUploadURL(path: "file.txt")

    #expect(response.path == "file.txt")
    #expect(response.token == "abc.def.ghi")
    #expect(
      response.signedURL.absoluteString
        == "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test
  func createSignedUploadURL_withUpsert() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-upsert: true" \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .createSignedUploadURL(
        path: "file.txt",
        upsert: true
      )

    #expect(response.path == "file.txt")
    #expect(response.token == "abc.def.ghi")
    #expect(
      response.signedURL.absoluteString
        == "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test
  func createSignedUploadURLCleansPath() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/upload/sign/bucket/folder/file.txt"),
      data: Data(
        """
        {
          "url": "object/upload/sign/bucket/folder/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/folder/file.txt"
      """#
    }

    let response = try await storage.from("bucket")
      .createSignedUploadURL(path: "/folder//file.txt")

    #expect(response.path == "folder/file.txt")
    #expect(response.token == "abc.def.ghi")
  }

  @Test
  func uploadToSignedURLCleansPath() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("object/upload/sign/bucket/folder/file.txt"),
      data: Data(
        """
        {
          "Key": "bucket/folder/file.txt"
        }
        """.utf8)
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 11" \
      	--header "Content-Type: text/plain" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "hello world" \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/folder/file.txt?token=abc.def.ghi"
      """#
    }

    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        path: "/folder//file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

    #expect(response.path == "folder/file.txt")
    #expect(response.fullPath == "bucket/folder/file.txt")
  }

  @Test
  func uploadToSignedURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "Key": "bucket/file.txt"
        }
        """.utf8)
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 11" \
      	--header "Content-Type: text/plain" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "hello world" \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }

    let response = try await storage.from("bucket")
      .uploadToSignedURL(path: "file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test
  func uploadToSignedURLDerivesContentTypeFromPathExtensionWhenOptionsOmitted() async throws {
    let request = LockIsolated(HTTPRequest?.none)
    let storage = try makeRequestCapturingSUT(request: request)

    _ = try await storage.from("bucket")
      .uploadToSignedURL(
        path: "cat.png",
        token: "abc.def.ghi",
        data: Data("not-really-a-png".utf8)
      )

    #expect(request.value?.headerFields[.contentType] == "image/png")
  }

  @Test
  func uploadToSignedURLFromFileURLDerivesContentTypeWhenOptionsOmitted() async throws {
    let request = LockIsolated(HTTPRequest?.none)
    let storage = try makeRequestCapturingSUT(request: request)

    _ = try await storage.from("bucket")
      .uploadToSignedURL(
        path: "cat.jpg",
        token: "abc.def.ghi",
        fileURL: Bundle.module.url(forResource: "sadcat", withExtension: "jpg")!
      )

    #expect(request.value?.headerFields[.contentType] == "image/jpeg")
  }

  @Test
  func uploadToSignedURL_fromFileURL() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "Key": "bucket/file.txt"
        }
        """.utf8)
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 13" \
      	--header "Content-Type: text/plain" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "X-Mode: test" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "hello world!
      " \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }

    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        path: "file.txt",
        token: "abc.def.ghi",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: UploadOptions(
          headers: [.init("X-Mode")!: "test"]
        )
      )

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test
  func createSignedURL_cacheNonce() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket/file.txt"),
      data: Data(
        """
        {
          "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
        }
        """.utf8
      )
    )

    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt", expiresIn: .seconds(3600), options: SignedURLOptions(cacheNonce: "abc123")
    )
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123")
  }

  @Test
  func createSignedURLs_cacheNonce() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("object/sign/bucket"),
      data: Data(
        """
        [
          {
            "path": "file.txt",
            "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
          }
        ]
        """.utf8
      )
    )

    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: ["file.txt"], expiresIn: .seconds(3600),
      options: SignedURLsOptions(cacheNonce: "abc123"))
    guard case .success(_, let url) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123")
  }

  @Test
  func getPublicURL_cacheNonce() throws {
    let storage = try makeSUT()

    let url = storage.from("bucket").publicURL(
      path: "file.txt", options: PublicURLOptions(cacheNonce: "abc123"))
    #expect(
      url.absoluteString == "\(self.url)/object/public/bucket/file.txt?cacheNonce=abc123")
  }

  @Test
  func download_cacheNonce() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("object/bucket/file.txt"),
      data: Data("hello world".utf8)
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt?cacheNonce=abc123"
      """#
    }

    let response = try await storage.from("bucket")
      .download(path: "file.txt", options: DownloadOptions(cacheNonce: "abc123"))

    #expect(try await response.data() == Data("hello world".utf8))
  }
}
