import Foundation
import Helpers
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct StorageFileAPITests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let storage: StorageClient

  init() {
    Mocker.removeAll()
    testingBoundary.setValue("alamofire.boundary.e56f43407f772505")
    JSONEncoder.unconfiguredEncoder.outputFormatting = [.sortedKeys]
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    storage = StorageClient(
      url: URL(string: "http://localhost:54321/storage/v1")!,
      configuration: StorageClientConfiguration(
        headers: [
          "apikey":
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        session: session,
        logger: nil
      )
    )
  }

  @Test func listFiles() async throws {
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
      	--header "Accept: application/json" \
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

  @Test func move() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 107" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"new\/path.txt\",\"sourceKey\":\"old\/path.txt\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }
    .register()

    try await storage.from("bucket").move(
      from: "old/path.txt",
      to: "new/path.txt"
    )
  }

  @Test func copy() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 111" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"dest\/file.txt\",\"sourceKey\":\"source\/file.txt\"}" \
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

  @Test func createSignedURL() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
      """#
    }
    .register()

    let signedURL = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: .seconds(3600)
    )
    #expect(
      signedURL.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test func createSignedURL_download() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"expiresIn\":3600}" \
      	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
      """#
    }
    .register()

    let signedURL = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: .seconds(3600),
      download: .download
    )
    #expect(
      signedURL.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download="
    )
  }

  @Test func createSignedURLs() async throws {
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
      	--header "Accept: application/json" \
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
    let results: [SignedURLResult] = try await storage.from("bucket")
      .createSignedURLs(
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
      url0.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
    guard case .success(let path1, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(path1 == "file2.txt")
    #expect(
      url1.absoluteString
        == "\(url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi"
    )
  }

  @Test func createSignedURLs_download() async throws {
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
      	--header "Accept: application/json" \
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
    let results: [SignedURLResult] = try await storage.from("bucket")
      .createSignedURLs(
        paths: paths,
        expiresIn: .seconds(3600),
        download: .download
      )
    #expect(results.count == 2)
    guard case .success(_, let url0) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      url0.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download="
    )
    guard case .success(_, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(
      url1.absoluteString
        == "\(url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi&download="
    )
  }

  @Test func createSignedURLs_withNullSignedURL() async throws {
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

    let results: [SignedURLResult] = try await storage.from("bucket")
      .createSignedURLs(
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
    #expect(
      error1
        == "Either the object does not exist or you do not have access to it"
    )
  }

  @Test func remove() async throws {
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
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Accept: application/json" \
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

  @Test func nonSuccessStatusCode() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }
    .register()

    let error = await #expect(throws: StorageError.self) {
      try await storage.from("bucket").move(from: "source", to: "destination")
    }
    #expect(error?.message == "Error")
  }

  @Test func nonSuccessStatusCodeWithNonJSONResponse() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }
    .register()

    let error = await #expect(throws: StorageError.self) {
      try await storage.from("bucket").move(from: "source", to: "destination")
    }
    #expect(error?.errorCode == .unknown)
    #expect(error?.statusCode == 412)
    #expect(error?.underlyingData == Data("error".utf8))
  }

  @Test func updateFromData() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 200,
      data: [
        .put: Data(
          """
          {
            "Id": "eaa8bdb5-2e00-4767-b5a9-d2502efe2196",
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
      	--header "Accept: application/json" \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 390" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "--alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"cacheControl\"\#r
      \#r
      3600\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"metadata\"\#r
      \#r
      {\"mode\":\"test\"}\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"\"; filename=\"file.txt\"\#r
      Content-Type: text/plain\#r
      \#r
      hello world\#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .update(
        "file.txt",
        data: Data("hello world".utf8),
        options: FileOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == UUID(uuidString: "eaa8bdb5-2e00-4767-b5a9-d2502efe2196"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func updateFromURL() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 200,
      data: [
        .put: Data(
          """
          {
            "Id": "eaa8bdb5-2e00-4767-b5a9-d2502efe2196",
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
      	--header "Accept: application/json" \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 392" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "--alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"cacheControl\"\#r
      \#r
      3600\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"metadata\"\#r
      \#r
      {\"mode\":\"test\"}\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"\"; filename=\"file.txt\"\#r
      Content-Type: text/plain\#r
      \#r
      hello world!
      \#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .update(
        "file.txt",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: FileOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == UUID(uuidString: "eaa8bdb5-2e00-4767-b5a9-d2502efe2196"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func download() async throws {
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
      	--header "Accept: application/json" \
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

  @Test func downloadWithAdditionalQuery() async throws {
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
      	--header "Accept: application/json" \
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

  @Test func download_withEmptyTransformOptions() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 200,
      data: [
        .get: Data("hello world".utf8)
      ]
    )
    .register()

    let data = try await storage.from("bucket")
      .download(path: "file.txt", options: TransformOptions())

    #expect(data == Data("hello world".utf8))
  }

  @Test func getPublicURL_withEmptyTransformOptions() throws {
    let publicURL = try storage.from("bucket")
      .getPublicURL(path: "image.png", options: TransformOptions())

    #expect(
      publicURL.absoluteString.contains("/object/public/"),
      "Empty transform should use /object/public/ path"
    )
    #expect(
      !publicURL.absoluteString.contains("/render/image/"),
      "Empty transform should not use /render/image/ path"
    )
  }

  @Test func getPublicURL_withActualTransformOptions() throws {
    let publicURL = try storage.from("bucket")
      .getPublicURL(path: "image.png", options: TransformOptions(width: 200))

    #expect(
      publicURL.absoluteString.contains("/render/image/"),
      "Non-empty transform should use /render/image/ path"
    )
  }

  @Test func download_withOptions() async throws {
    let imageData = try Data(
      contentsOf: Bundle.module.url(
        forResource: "sadcat",
        withExtension: "jpg"
      )!
    )

    Mock(
      url: url.appendingPathComponent(
        "render/image/authenticated/bucket/sadcat.txt"
      ),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: imageData
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/render/image/authenticated/bucket/sadcat.txt?format=origin"
      """#
    }
    .register()

    let data = try await storage.from("bucket")
      .download(
        path: "sadcat.txt",
        options: TransformOptions(format: .origin)
      )

    #expect(data == imageData)
  }

  @Test func info() async throws {
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
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/info/bucket/file.txt"
      """#
    }
    .register()

    let info = try await storage.from("bucket").info(path: "file.txt")

    #expect(info.name == "file.txt")
  }

  @Test func exists() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 200,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(exists)
  }

  @Test func exists_400_error() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 400,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test func exists_404_error() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 404,
      data: [
        .head: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test func createSignedUploadURL() async throws {
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
      	--header "Accept: application/json" \
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

  @Test func createSignedUploadURL_withUpsert() async throws {
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
      	--header "Accept: application/json" \
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
          upsert: true
        )
      )

    #expect(response.path == "file.txt")
    #expect(response.token == "abc.def.ghi")
    #expect(
      response.signedURL.absoluteString
        == "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test func uploadToSignedURL() async throws {
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
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Accept: application/json" \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 283" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-upsert: false" \
      	--data "--alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"cacheControl\"\#r
      \#r
      3600\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"\"; filename=\"file.txt\"\#r
      Content-Type: text/plain\#r
      \#r
      hello world\#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        "file.txt",
        token: "abc.def.ghi",
        data: Data("hello world".utf8)
      )

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func uploadToSignedURL_fromFileURL() async throws {
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
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Accept: application/json" \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 285" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-upsert: false" \
      	--data "--alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"cacheControl\"\#r
      \#r
      3600\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"\"; filename=\"file.txt\"\#r
      Content-Type: text/plain\#r
      \#r
      hello world!
      \#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        "file.txt",
        token: "abc.def.ghi",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!
      )

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func uploadToSignedURL_fromFileURLWithoutOptionsDerivesMimeTypeFromFileExtension()
    async throws
  {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("signed-upload.json")
    try Data("{}".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

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
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Accept: application/json" \
      	--header "Cache-Control: max-age=3600" \
      	--header "Content-Length: 290" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-upsert: false" \
      	--data "--alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"cacheControl\"\#r
      \#r
      3600\#r
      --alamofire.boundary.e56f43407f772505\#r
      Content-Disposition: form-data; name=\"\"; filename=\"signed-upload.json\"\#r
      Content-Type: application/json\#r
      \#r
      {}\#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        "file.txt",
        token: "abc.def.ghi",
        fileURL: fileURL
      )

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func createSignedURL_cacheNonce() async throws {
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

    let signedURL = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: .seconds(3600),
      cacheNonce: "abc123"
    )
    #expect(
      signedURL.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123"
    )
  }

  @Test func createSignedURLs_cacheNonce() async throws {
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

    let results: [SignedURLResult] = try await storage.from("bucket")
      .createSignedURLs(
        paths: ["file.txt"],
        expiresIn: .seconds(3600),
        cacheNonce: "abc123"
      )
    guard case .success(_, let signedURL) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      signedURL.absoluteString
        == "\(url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123"
    )
  }

  @Test func getPublicURL_cacheNonce() throws {
    let signedURL = try storage.from("bucket").getPublicURL(
      path: "file.txt",
      cacheNonce: "abc123"
    )
    #expect(
      signedURL.absoluteString
        == "\(url)/object/public/bucket/file.txt?cacheNonce=abc123"
    )
  }

  @Test func uploadWithProgressClosure() async throws {
    Mock(
      url: url.appendingPathComponent("object/bucket/file.txt"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "Id": "eaa8bdb5-2e00-4767-b5a9-d2502efe2196",
            "Key": "bucket/file.txt"
          }
          """.utf8
        )
      ]
    )
    .register()

    let response = try await storage.from("bucket").upload(
      "file.txt",
      data: Data("hello world".utf8),
      progress: { _ in }
    )

    #expect(response.id == UUID(uuidString: "eaa8bdb5-2e00-4767-b5a9-d2502efe2196"))
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test func download_cacheNonce() async throws {
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
      	--header "Accept: application/json" \
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
