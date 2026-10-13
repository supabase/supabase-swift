import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation
import Mocker
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension StorageMockerTests {
  @Suite(.mockerSerialized)
  struct StorageBucketTests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    private func makeSUT() -> StorageClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return StorageClient(
        configuration: StorageClientConfiguration(
          url: url,
          headers: [
            "apikey":
              "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
          ],
          http: .init(transport: URLSessionTransport(session: session)))
      )
    }

    /// A client whose transport records the request head, for asserting the emitted upload
    /// headers.
    private func makeRequestCapturingSUT(request captured: LockIsolated<HTTPRequest?>)
      -> StorageClient
    {
      StorageClient(
        configuration: StorageClientConfiguration(
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
      -> StorageClient
    {
      StorageClient(
        configuration: StorageClientConfiguration(
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
      -> StorageClient
    {
      StorageClient(
        configuration: StorageClientConfiguration(
          url: url,
          headers: [:],
          http: .init(transport: ClosureTransport { _, _ in try failure() })
        )
      )
    }

    @Test
    func transportFailureIsWrapped() async {
      let storage = makeFailingSUT { throw URLError(.timedOut) }

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
    func cancellationIsNotWrapped() async {
      let storage = makeFailingSUT { throw CancellationError() }

      await #expect(throws: CancellationError.self) {
        _ = try await storage.from("bucket").list()
      }
    }

    /// A `URLError(.cancelled)` that is not caused by cancelling the caller's `Task` (a
    /// middleware or a custom transport cancelled the request) is a transport failure.
    @Test
    func cancelledURLErrorWithoutTaskCancellationIsWrapped() async {
      let storage = makeFailingSUT { throw URLError(.cancelled) }

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

    /// Cancelling the enclosing `Task` mid-flight makes the real ``URLSessionTransport`` fail
    /// with `URLError(.cancelled)`; Storage reports it as `CancellationError` (SDK-2008).
    @Test
    func cancellingTheTaskThrowsCancellationError() async {
      let storage = makeSUT()
      let (requestStarted, onRequestStarted) = AsyncStream<Void>.makeStream()

      var mock = Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      // `MockingURLProtocol` runs the request callback before it schedules the delayed
      // response, so the cancel below always lands while the request is in flight. The delay
      // is never waited out: cancelling makes `stopLoading()` drop the pending response.
      mock.delay = .seconds(10)
      mock.onRequestHandler = OnRequestHandler(requestCallback: { _ in onRequestStarted.yield() })
      mock.register()

      let task = Task { try await storage.from("bucket").list() }
      for await _ in requestStarted { break }
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
    func customFetchErrorIsNotWrapped() async {
      struct FetchError: Error {}
      let storage = makeFailingSUT { throw FetchError() }

      await #expect(throws: FetchError.self) {
        _ = try await storage.from("bucket").list()
      }
    }

    @Test
    func undecodableSuccessBodyIsWrapped() async {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("not json".utf8)]
      )
      .register()

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
    func configuration() {
      let storage = makeSUT()
      #expect(storage.from("bucket").configuration.url == url)
    }

    @Test
    func listFiles() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
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
        ]
      )
      .snapshotRequest {
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
      .register()

      let result = try await storage.from("bucket").list(path: "folder")
      #expect(result.count == 1)
      #expect(result[0].name == "test.txt")
    }

    @Test
    func listFilesWithPartialSortByColumn() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(sortBy: SortBy(column: "updated_at"))
      )
    }

    @Test
    func listFilesWithPartialSortByOrder() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(sortBy: SortBy(order: .descending))
      )
    }

    @Test
    func listFilesWithFullSortByOverride() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(sortBy: SortBy(column: "updated_at", order: .descending))
      )
    }

    @Test
    func listFilesPreservesDefaultLimitWhenOnlyOffsetProvided() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(offset: 10, sortBy: SortBy(column: "name", order: .ascending))
      )
    }

    @Test
    func listFilesPreservesDefaultOffsetWhenOnlyLimitProvided() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(limit: 50, sortBy: SortBy(column: "name", order: .ascending))
      )
    }

    @Test
    func listFilesWithExplicitZeroLimitIsNotTreatedAsMissing() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/list/bucket"),
        statusCode: 200,
        data: [.post: Data("[]".utf8)]
      )
      .snapshotRequest {
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
      .register()

      _ = try await storage.from("bucket").list(
        path: "folder",
        options: SearchOptions(
          limit: 0, offset: 5, sortBy: SortBy(column: "name", order: .ascending))
      )
    }

    @Test
    func move() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/move"),
        statusCode: 200,
        data: [
          .post: Data()
        ]
      )
      .snapshotRequest {
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
      .register()

      try await storage.from("bucket").move(
        from: "old/path.txt",
        to: "new/path.txt"
      )
    }

    @Test
    func copy() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/copy"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "Key": "object/dest/file.txt"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

      let key = try await storage.from("bucket").copy(
        from: "source/file.txt",
        to: "dest/file.txt"
      )

      #expect(key == "object/dest/file.txt")
    }

    @Test
    func createSignedURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

      let url = try await storage.from("bucket").createSignedURL(
        path: "file.txt",
        expiresIn: 3600
      )
      #expect(
        url.absoluteString == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
    }

    @Test
    func createSignedURL_malformedSignedURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "signedURL": "http://[::1"
            }
            """.utf8
          )
        ]
      )
      .register()

      do {
        _ = try await storage.from("bucket").createSignedURL(
          path: "file.txt",
          expiresIn: 3600
        )
        Issue.record("expected createSignedURL to throw")
      } catch let error as StorageError {
        #expect(error.kind == .decoding)
        #expect(error.response == nil)
      }
    }

    @Test
    func createSignedURL_download() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

      let url = try await storage.from("bucket").createSignedURL(
        path: "file.txt",
        expiresIn: 3600,
        download: .withOriginalName
      )
      #expect(
        url.absoluteString
          == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
    }

    @Test
    func createSignedURLs() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
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
        ]
      )
      .snapshotRequest {
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
      .register()

      let paths = ["file.txt", "file2.txt"]
      let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
        paths: paths,
        expiresIn: 3600
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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
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
        ]
      )
      .snapshotRequest {
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
      .register()

      let paths = ["file.txt", "file2.txt"]
      let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
        paths: paths,
        expiresIn: 3600,
        download: .withOriginalName
      )
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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
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
        ]
      )
      .register()

      let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
        paths: ["file.txt", "missing.txt"],
        expiresIn: 3600
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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket"),
        statusCode: 204,
        data: [
          .delete: Data(
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
        ]
      )
      .snapshotRequest {
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
      .register()

      let objects = try await storage.from("bucket").remove(
        paths: ["file1.txt", "file2.txt"]
      )

      #expect(objects[0].name == "file1.txt")
      #expect(objects[1].name == "file2.txt")
    }

    @Test
    func nonSuccessStatusCode() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/move"),
        statusCode: 400,
        data: [
          .post: Data(
            """
            {
              "message":"Error"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

      do {
        try await storage.from("bucket")
          .move(from: "source", to: "destination")
        Issue.record()
      } catch let error as StorageError {
        #expect(error.kind == .server)
        #expect(error.message == "Error")
        #expect(error.serverError?.message == "Error")
        #expect(error.response?.statusCode == 400)
      }
    }

    @Test
    func nonSuccessStatusCodeWithNonJSONResponse() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/move"),
        statusCode: 412,
        data: [
          .post: Data("error".utf8)
        ]
      )
      .snapshotRequest {
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
      .register()

      do {
        try await storage.from("bucket")
          .move(from: "source", to: "destination")
        Issue.record()
      } catch let error as StorageError {
        #expect(error.kind == .server)
        #expect(error.serverError == nil)
        #expect(error.response?.body == Data("error".utf8))
        #expect(error.response?.statusCode == 412)
      }
    }

    @Test
    func nonSuccessStatusCodeExposesTheServerErrorCode() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/missing.txt"),
        statusCode: 400,
        data: [
          .get: Data(
            """
            {
              "statusCode":"404",
              "error":"not_found",
              "message":"Object not found",
              "code":"NoSuchKey"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/bucket/missing.txt"
        """#
      }
      .register()

      do {
        _ = try await storage.from("bucket").download(path: "missing.txt")
        Issue.record()
      } catch let error as StorageError {
        #expect(error.kind == .server)
        #expect(error.serverError?.code == .noSuchKey)
        #expect(error.serverError?.error == "not_found")
        #expect(error.response?.statusCode == 400)
      }
    }

    @Test
    func updateFromData() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .put: Data(
            """
            {
              "Id": "123",
              "Key": "bucket/file.txt"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

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

      #expect(response.id == "123")
      #expect(response.path == "file.txt")
      #expect(response.fullPath == "bucket/file.txt")
    }

    @Test
    func uploadReturnsCleanedPath() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/folder/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "Id": "123",
              "Key": "bucket/folder/file.txt"
            }
            """.utf8
          )
        ]
      )
      .register()

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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "Id": "123",
              "Key": "bucket/file.txt"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

      let response = try await storage.from("bucket")
        .upload(
          path: "file.txt",
          fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
          options: UploadOptions(contentType: "image/png")
        )

      #expect(response.id == "123")
      #expect(response.path == "file.txt")
      #expect(response.fullPath == "bucket/file.txt")
    }

    @Test
    func updateFromURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .put: Data(
            """
            {
              "Id": "123",
              "Key": "bucket/file.txt"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
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
      .register()

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

      #expect(response.id == "123")
      #expect(response.path == "file.txt")
      #expect(response.fullPath == "bucket/file.txt")
    }

    @Test
    func download() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/bucket/file.txt"
        """#
      }
      .register()

      let data = try await storage.from("bucket")
        .download(path: "file.txt")

      #expect(data == Data("hello world".utf8))
    }

    @Test
    func downloadWithAdditionalQuery() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/bucket/file.txt?version=1"
        """#
      }
      .register()

      let data = try await storage.from("bucket")
        .download(
          path: "file.txt",
          query: [URLQueryItem(name: "version", value: "1")]
        )

      #expect(data == Data("hello world".utf8))
    }

    @Test
    func download_withEmptyImageTransform() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .register()

      let data = try await storage.from("bucket")
        .download(path: "file.txt", transform: ImageTransform())

      #expect(data == Data("hello world".utf8))
    }

    @Test
    func getPublicURL_withEmptyImageTransform() throws {
      let storage = makeSUT()

      let publicURL = try storage.from("bucket")
        .publicURL(path: "image.png", transform: ImageTransform())

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
      let storage = makeSUT()

      let publicURL = try storage.from("bucket")
        .publicURL(path: "image.png", transform: ImageTransform(width: 200))

      #expect(
        publicURL.absoluteString.contains("/render/image/"),
        "Non-empty transform should use /render/image/ path, got: \(publicURL.absoluteString)"
      )
    }

    @Test
    func getPublicURLStripsLeadingSlash() throws {
      let storage = makeSUT()

      let publicURL = try storage.from("bucket")
        .publicURL(path: "/folder/image.png")

      #expect(
        publicURL.absoluteString
          == "http://localhost:54321/storage/v1/object/public/bucket/folder/image.png"
      )
    }

    @Test
    func downloadStripsLeadingSlash() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/bucket/file.txt"
        """#
      }
      .register()

      let data = try await storage.from("bucket")
        .download(path: "/file.txt")

      #expect(data == Data("hello world".utf8))
    }

    @Test
    func getPublicURLCollapsesRepeatedAndTrailingSlashes() throws {
      let storage = makeSUT()

      let publicURL = try storage.from("bucket")
        .publicURL(path: "folder//image.png/")

      #expect(
        publicURL.absoluteString
          == "http://localhost:54321/storage/v1/object/public/bucket/folder/image.png"
      )
    }

    @Test
    func downloadCollapsesRepeatedAndTrailingSlashes() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/folder/file.txt"),
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .register()

      let data = try await storage.from("bucket")
        .download(path: "folder//file.txt/")

      #expect(data == Data("hello world".utf8))
    }

    @Test
    func moveCleansPaths() async throws {
      struct Sent: Decodable {
        let sourceKey: String
        let destinationKey: String
      }
      let body = LockIsolated(Data?.none)
      let storage = makeBodyCapturingSUT(body: body, response: "{}")

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
      let storage = makeBodyCapturingSUT(
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
      let storage = makeBodyCapturingSUT(body: body, response: "[]")

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
      let storage = makeBodyCapturingSUT(body: body, response: "[]")

      _ = try await storage.from("bucket")
        .createSignedURLs(paths: ["/folder//a.png", "b.png/"], expiresIn: 60)

      let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
      #expect(sent.paths == ["folder/a.png", "b.png"])
    }

    @Test
    func listCleansPath() async throws {
      struct Sent: Decodable {
        let prefix: String
      }
      let body = LockIsolated(Data?.none)
      let storage = makeBodyCapturingSUT(body: body, response: "[]")

      _ = try await storage.from("bucket").list(path: "/folder//nested/")

      let sent = try JSONDecoder().decode(Sent.self, from: #require(body.value))
      #expect(sent.prefix == "folder/nested")
    }

    @Test
    func download_withOptions() async throws {
      let storage = makeSUT()

      let imageData = try! Data(
        contentsOf: Bundle.module.url(forResource: "sadcat", withExtension: "jpg")!)

      Mock(
        url: url.appendingPathComponent("render/image/authenticated/bucket/sadcat.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: imageData
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/render/image/authenticated/bucket/sadcat.txt?resize=cover"
        """#
      }
      .register()

      let data = try await storage.from("bucket")
        .download(
          path: "sadcat.txt",
          transform: ImageTransform(resize: .cover)
        )

      #expect(data == imageData)
    }

    @Test
    func info() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/info/bucket/file.txt"),
        statusCode: 200,
        data: [
          .get: Data(
            """
            {
              "name": "file.txt",
              "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "version": "2"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/info/bucket/file.txt"
        """#
      }
      .register()

      let info = try await storage.from("bucket").info(path: "file.txt")

      #expect(info.name == "file.txt")
    }

    @Test
    func exists() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/info/bucket/file.txt"),
        statusCode: 200,
        data: [
          .get: Data(
            #"{"id":"b5a2d6ea-7c5e-4d3a-9b3e-1f2e3d4c5b6a","version":"v1","name":"file.txt"}"#.utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/info/bucket/file.txt"
        """#
      }
      .register()

      let exists = try await storage.from("bucket").exists(path: "file.txt")

      #expect(exists)
    }

    /// Storage answers a missing key with HTTP 400 and `NoSuchKey` in the body.
    @Test
    func existsIsFalseForNoSuchKey() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/info/bucket/file.txt"),
        statusCode: 400,
        data: [
          .get: Data(
            #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#
              .utf8)
        ]
      )
      .register()

      let exists = try await storage.from("bucket").exists(path: "file.txt")

      #expect(!exists)
    }

    /// An older server that sends no `code` still says 404 in the body.
    @Test
    func existsIsFalseForABody404WithoutACode() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/info/bucket/file.txt"),
        statusCode: 400,
        data: [
          .get: Data(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#.utf8)
        ]
      )
      .register()

      let exists = try await storage.from("bucket").exists(path: "file.txt")

      #expect(!exists)
    }

    /// A missing bucket and an expired session both arrive as HTTP 400; neither means "the file
    /// does not exist".
    @Test(arguments: [
      ("NoSuchBucket", "404", StorageError.Code.noSuchBucket), ("InvalidJWT", "400", .invalidJWT),
    ])
    func existsRethrowsOtherServerErrors(raw: String, status: String, code: StorageError.Code)
      async throws
    {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/info/bucket/file.txt"),
        statusCode: 400,
        data: [
          .get: Data(
            #"{"statusCode":"\#(status)","error":"\#(raw)","message":"\#(raw)","code":"\#(raw)"}"#
              .utf8)
        ]
      )
      .register()

      await #expect {
        try await storage.from("bucket").exists(path: "file.txt")
      } throws: { error in
        (error as? StorageError)?.code == code
      }
    }

    @Test
    func purgeCache() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("cdn/bucket/folder/file.txt"),
        statusCode: 200,
        data: [
          .delete: Data(#"{"message":"success"}"#.utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/cdn/bucket/folder/file.txt"
        """#
      }
      .register()

      try await storage.from("bucket").purgeCache(path: "folder/file.txt")
    }

    @Test
    func purgeCacheTransformationsOnly() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("cdn/bucket/folder/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .delete: Data(#"{"message":"success"}"#.utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/cdn/bucket/folder/file.txt?transformations=true"
        """#
      }
      .register()

      try await storage.from("bucket").purgeCache(
        path: "folder/file.txt", transformationsOnly: true)
    }

    @Test
    func purgeCachePercentEncodesThePath() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("cdn/bucket/folder/my file.png"),
        statusCode: 200,
        data: [
          .delete: Data(#"{"message":"success"}"#.utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/cdn/bucket/folder/my%20file.png"
        """#
      }
      .register()

      try await storage.from("bucket").purgeCache(path: "folder/my file.png")
    }

    @Test
    func createSignedUploadURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt"
        """#
      }
      .register()

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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "x-upsert: true" \
        	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt"
        """#
      }
      .register()

      let response = try await storage.from("bucket")
        .createSignedUploadURL(
          path: "file.txt",
          options: CreateSignedUploadURLOptions(
            shouldUpsert: true
          )
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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/folder/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "url": "object/upload/sign/bucket/folder/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/upload/sign/bucket/folder/file.txt"
        """#
      }
      .register()

      let response = try await storage.from("bucket")
        .createSignedUploadURL(path: "/folder//file.txt")

      #expect(response.path == "folder/file.txt")
      #expect(response.token == "abc.def.ghi")
    }

    @Test
    func uploadToSignedURLCleansPath() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/folder/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .put: Data(
            """
            {
              "Key": "bucket/folder/file.txt"
            }
            """.utf8)
        ]
      )
      .snapshotRequest {
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
      .register()

      let response = try await storage.from("bucket")
        .uploadToSignedURL(
          path: "/folder//file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

      #expect(response.path == "folder/file.txt")
      #expect(response.fullPath == "bucket/folder/file.txt")
    }

    @Test
    func uploadToSignedURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .put: Data(
            """
            {
              "Key": "bucket/file.txt"
            }
            """.utf8)
        ]
      )
      .snapshotRequest {
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
      .register()

      let response = try await storage.from("bucket")
        .uploadToSignedURL(path: "file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

      #expect(response.path == "file.txt")
      #expect(response.fullPath == "bucket/file.txt")
    }

    @Test
    func uploadToSignedURLDerivesContentTypeFromPathExtensionWhenOptionsOmitted() async throws {
      let request = LockIsolated(HTTPRequest?.none)
      let storage = makeRequestCapturingSUT(request: request)

      _ = try await storage.from("bucket")
        .uploadToSignedURL(
          path: "cat.png",
          token: "abc.def.ghi",
          data: Data("not-really-a-png".utf8)
        )

      #if canImport(UniformTypeIdentifiers)
        #expect(request.value?.headerFields[.contentType] == "image/png")
      #else
        #expect(request.value?.headerFields[.contentType] == "application/octet-stream")
      #endif
    }

    @Test
    func uploadToSignedURLFromFileURLDerivesContentTypeWhenOptionsOmitted() async throws {
      let request = LockIsolated(HTTPRequest?.none)
      let storage = makeRequestCapturingSUT(request: request)

      _ = try await storage.from("bucket")
        .uploadToSignedURL(
          path: "cat.jpg",
          token: "abc.def.ghi",
          fileURL: Bundle.module.url(forResource: "sadcat", withExtension: "jpg")!
        )

      #if canImport(UniformTypeIdentifiers)
        #expect(request.value?.headerFields[.contentType] == "image/jpeg")
      #else
        #expect(request.value?.headerFields[.contentType] == "application/octet-stream")
      #endif
    }

    @Test
    func uploadToSignedURL_fromFileURL() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .put: Data(
            """
            {
              "Key": "bucket/file.txt"
            }
            """.utf8)
        ]
      )
      .snapshotRequest {
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
      .register()

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
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket/file.txt"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """.utf8
          )
        ]
      )
      .register()

      let url = try await storage.from("bucket").createSignedURL(
        path: "file.txt",
        expiresIn: 3600,
        cacheNonce: "abc123"
      )
      #expect(
        url.absoluteString
          == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123")
    }

    @Test
    func createSignedURLs_cacheNonce() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/sign/bucket"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            [
              {
                "path": "file.txt",
                "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
              }
            ]
            """.utf8
          )
        ]
      )
      .register()

      let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
        paths: ["file.txt"],
        expiresIn: 3600,
        cacheNonce: "abc123"
      )
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
      let storage = makeSUT()

      let url = try storage.from("bucket").publicURL(
        path: "file.txt",
        cacheNonce: "abc123"
      )
      #expect(
        url.absoluteString == "\(self.url)/object/public/bucket/file.txt?cacheNonce=abc123")
    }

    @Test
    func download_cacheNonce() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("object/bucket/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data("hello world".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/storage/v1/object/bucket/file.txt?cacheNonce=abc123"
        """#
      }
      .register()

      let data = try await storage.from("bucket")
        .download(path: "file.txt", cacheNonce: "abc123")

      #expect(data == Data("hello world".utf8))
    }
  }
}
