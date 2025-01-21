import Helpers
import InlineSnapshotTesting
import XCTest

@testable import Storage

final class StorageFileAPITests: XCTestCase {
  let url = URL(string: "http://localhost:54321/storage/v1")!

  var storage: SupabaseStorageClient!
  var mockResponses: [(Data, URLResponse)]!

  var snapshot: ((URLRequest) -> Void)?

  override func setUp() {
    super.setUp()
    mockResponses = []

    let mockSession = StorageHTTPSession(
      fetch: { [weak self] request in
        self?.snapshot?(request)

        guard let response = self?.mockResponses.removeFirst() else {
          throw StorageError(message: "No mock response available")
        }
        return response
      },
      upload: { [weak self] request, data in
        self?.snapshot?(request)

        guard let response = self?.mockResponses.removeFirst() else {
          throw StorageError(message: "No mock response available")
        }
        return response
      }
    )

    JSONEncoder.defaultStorageEncoder.outputFormatting = [.sortedKeys]
    JSONEncoder.unconfiguredEncoder.outputFormatting = [.sortedKeys]

    storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: ["X-Client-Info": "storage-swift/0.0.0"],
        session: mockSession,
        logger: nil
      )
    )
  }

  func testListFiles() async throws {
    // Setup mock response
    let jsonResponse = """
      [{
          "name": "test.txt",
          "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "updatedAt": "2024-01-01T00:00:00Z",
          "createdAt": "2024-01-01T00:00:00Z",
          "lastAccessedAt": "2024-01-01T00:00:00Z",
          "metadata": {}
      }]
      """.data(using: .utf8)!

    mockResponses = [
      (
        jsonResponse,
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    snapshot = {
      assertInlineSnapshot(of: $0, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"limit\":100,\"offset\":0,\"prefix\":\"folder\",\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}" \
        	"http://localhost:54321/storage/v1/object/list/bucket"
        """#
      }
    }

    let result = try await storage.from("bucket").list(path: "folder")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].name, "test.txt")
  }

  func testMove() async throws {
    mockResponses = [
      (
        Data(),
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    snapshot = {
      assertInlineSnapshot(of: $0, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"new\/path.txt\",\"sourceKey\":\"old\/path.txt\"}" \
        	"http://localhost:54321/storage/v1/object/move"
        """#
      }
    }

    try await storage.from("bucket").move(
      from: "old/path.txt",
      to: "new/path.txt"
    )
  }

  func testCopy() async throws {
    mockResponses = [
      (
        """
        {"Key": "object/dest/file.txt"}
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    snapshot = {
      assertInlineSnapshot(of: $0, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"bucketId\":\"bucket\",\"destinationBucket\":null,\"destinationKey\":\"dest\/file.txt\",\"sourceKey\":\"source\/file.txt\"}" \
        	"http://localhost:54321/storage/v1/object/copy"
        """#
      }
    }

    let key = try await storage.from("bucket").copy(
      from: "source/file.txt",
      to: "dest/file.txt"
    )
    XCTAssertEqual(key, "object/dest/file.txt")
  }

  func testCreateSignedURL() async throws {
    mockResponses = [
      (
        """
        {"signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"}
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    snapshot = {
      assertInlineSnapshot(of: $0, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"expiresIn\":3600}" \
        	"http://localhost:54321/storage/v1/object/sign/bucket/file.txt"
        """#
      }
    }

    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: 3600
    )
    XCTAssertEqual(
      url.absoluteString, "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  func testCreateSignedURLs() async throws {
    mockResponses = [
      (
        """
        [
        {"path": "file.txt", "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"},
        {"path": "file2.txt", "signedURL": "object/upload/sign/bucket/file2.txt?token=abc.def.ghi"}
        ]
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    snapshot = {
      assertInlineSnapshot(of: $0, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"expiresIn\":3600,\"paths\":[\"file.txt\",\"file2.txt\"]}" \
        	"http://localhost:54321/storage/v1/object/sign/bucket"
        """#
      }
    }

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

  func testNonSuccessStatusCode() async throws {
    mockResponses = [
      (
        """
        {"message":"Error"}
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: url,
          statusCode: 412,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
    } catch let error as StorageError {
      XCTAssertEqual(error.message, "Error")
    }
  }

  func testNonSuccessStatusCodeWithNonJSONResponse() async throws {
    mockResponses = [
      (
        "error".data(using: .utf8)!,
        HTTPURLResponse(
          url: url,
          statusCode: 412,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    ]

    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("error".utf8))
      XCTAssertEqual(error.response.statusCode, 412)
    }
  }
}
