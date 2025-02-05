import Helpers
import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class StorageFileAPITests: XCTestCase {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  var storage: SupabaseStorageClient!

  override func setUp() {
    super.setUp()

    testingBoundary.setValue("alamofire.boundary.e56f43407f772505")

    JSONEncoder.defaultStorageEncoder.outputFormatting = [.sortedKeys]
    JSONEncoder.unconfiguredEncoder.outputFormatting = [.sortedKeys]

    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockingURLProtocol.self]

    let session = URLSession(configuration: configuration)

    storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: [
          "apikey":
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        session: StorageHTTPSession(
          fetch: { try await session.data(for: $0) },
          upload: { try await session.upload(for: $0, from: $1) }
        ),
        logger: nil
      )
    )
  }

  func testListFiles() async throws {
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
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].name, "test.txt")
  }

  func testMove() async throws {
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

  func testCopy() async throws {
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

    XCTAssertEqual(key, "object/dest/file.txt")
  }

  func testCreateSignedURL() async throws {
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
    XCTAssertEqual(
      url.absoluteString, "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  func testCreateSignedURL_download() async throws {
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
      download: true
    )
    XCTAssertEqual(
      url.absoluteString,
      "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
  }

  func testCreateSignedURLs() async throws {
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
    let urls = try await storage.from("bucket").createSignedURLs(
      paths: paths,
      expiresIn: 3600
    )
    XCTAssertEqual(urls.count, 2)
    XCTAssertEqual(
      urls[0].absoluteString, "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
    XCTAssertEqual(
      urls[1].absoluteString, "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi")
  }

  func testCreateSignedURLs_download() async throws {
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
    let urls = try await storage.from("bucket").createSignedURLs(
      paths: paths,
      expiresIn: 3600,
      download: true
    )
    XCTAssertEqual(urls.count, 2)
    XCTAssertEqual(
      urls[0].absoluteString,
      "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
    XCTAssertEqual(
      urls[1].absoluteString,
      "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi&download=")
  }

  func testRemove() async throws {
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

    XCTAssertEqual(objects[0].name, "file1.txt")
    XCTAssertEqual(objects[1].name, "file2.txt")
  }

  func testNonSuccessStatusCode() async throws {
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
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }
    .register()

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      XCTFail()
    } catch let error as StorageError {
      XCTAssertEqual(error.message, "Error")
    }
  }

  func testNonSuccessStatusCodeWithNonJSONResponse() async throws {
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
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"destination\",\"sourceKey\":\"source\"}" \
      	"http://localhost:54321/storage/v1/object/move"
      """#
    }
    .register()

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      XCTFail()
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("error".utf8))
      XCTAssertEqual(error.response.statusCode, 412)
    }
  }

  func testUpdateFromData() async throws {
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

    XCTAssertEqual(response.id, "123")
    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.fullPath, "bucket/file.txt")
  }

  func testUpdateFromURL() async throws {
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

    XCTAssertEqual(response.id, "123")
    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.fullPath, "bucket/file.txt")
  }

  func testDownload() async throws {
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

    XCTAssertEqual(data, Data("hello world".utf8))
  }

  func testDownload_withOptions() async throws {
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
      	"http://localhost:54321/storage/v1/render/image/authenticated/bucket/sadcat.txt?format=cover&quality=80"
      """#
    }
    .register()

    let data = try await storage.from("bucket")
      .download(
        path: "sadcat.txt",
        options: TransformOptions(format: "cover")
      )

    XCTAssertEqual(data, imageData)
  }

  func testInfo() async throws {
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

    XCTAssertEqual(info.name, "file.txt")
  }

  func testExists() async throws {
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
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    XCTAssertTrue(exists)
  }

  func testExists_400_error() async throws {
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
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    XCTAssertFalse(exists)
  }

  func testExists_404_error() async throws {
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
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/object/bucket/file.txt"
      """#
    }
    .register()

    let exists = try await storage.from("bucket").exists(path: "file.txt")

    XCTAssertFalse(exists)
  }

  func testCreateSignedUploadURL() async throws {
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

    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.token, "abc.def.ghi")
    XCTAssertEqual(
      response.signedURL.absoluteString,
      "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  func testCreateSignedUploadURL_withUpsert() async throws {
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
          upsert: true
        )
      )

    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.token, "abc.def.ghi")
    XCTAssertEqual(
      response.signedURL.absoluteString,
      "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  func testUploadToSignedURL() async throws {
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
      	--header "Content-Length: 297" \
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
      Content-Type: text/plain;charset=UTF-8\#r
      \#r
      hello world\#r
      --alamofire.boundary.e56f43407f772505--\#r
      " \
      	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
      """#
    }
    .register()

    let response = try await storage.from("bucket")
      .uploadToSignedURL("file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.fullPath, "bucket/file.txt")
  }

  func testUploadToSignedURL_fromFileURL() async throws {
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
      	--header "Content-Length: 285" \
      	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "X-Mode: test" \
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
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: FileOptions(
          headers: ["X-Mode": "test"]
        )
      )

    XCTAssertEqual(response.path, "file.txt")
    XCTAssertEqual(response.fullPath, "bucket/file.txt")
  }
}
