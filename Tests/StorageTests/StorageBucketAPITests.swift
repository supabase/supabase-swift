import InlineSnapshotTesting
import XCTest

@testable import Storage

final class StorageBucketAPITests: XCTestCase {
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

    JSONEncoder.defaultStorageEncoder.outputFormatting = [
      .sortedKeys
    ]

    storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://example.com")!,
        headers: ["X-Client-Info": "storage-swift/0.0.0"],
        session: mockSession,
        logger: nil
      )
    )
  }

  func testGetBucket() async throws {
    let jsonResponse = """
      {
          "id": "bucket123",
          "name": "test-bucket",
          "owner": "owner123",
          "public": false,
          "created_at": "2024-01-01T00:00:00.000Z",
          "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    mockResponses = [
      (
        jsonResponse,
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	"http://example.com/bucket/bucket123"
        """#
      }
    }

    let bucket = try await storage.getBucket("bucket123")
    XCTAssertEqual(bucket.id, "bucket123")
    XCTAssertEqual(bucket.name, "test-bucket")
  }

  func testListBuckets() async throws {
    let jsonResponse = """
      [{
          "id": "bucket123",
          "name": "test-bucket",
          "owner": "owner123",
          "public": false,
          "created_at": "2024-01-01T00:00:00.000Z",
          "updated_at": "2024-01-01T00:00:00.000Z"
      }]
      """.data(using: .utf8)!

    mockResponses = [
      (
        jsonResponse,
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	"http://example.com/bucket"
        """#
      }
    }

    let buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets.count, 1)
    XCTAssertEqual(buckets[0].name, "test-bucket")
  }

  func testCreateBucket() async throws {
    let jsonResponse = """
      {
          "id": "newbucket",
          "name": "new-bucket",
          "owner": "owner123",
          "public": true,
          "created_at": "2024-01-01T00:00:00.000Z",
          "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    mockResponses = [
      (
        jsonResponse,
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--data "{\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":true}" \
        	"http://example.com/bucket"
        """#
      }
    }

    let options = BucketOptions(public: true)
    try await storage.createBucket(
      "newbucket",
      options: options
    )
  }

  func testUpdateBucket() async throws {
    let jsonResponse = """
      {
          "id": "bucket123",
          "name": "updated-bucket",
          "owner": "owner123",
          "public": true,
          "created_at": "2024-01-01T00:00:00.000Z",
          "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    mockResponses = [
      (
        jsonResponse,
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--request PUT \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--data "{\"id\":\"bucket123\",\"name\":\"bucket123\",\"public\":true}" \
        	"http://example.com/bucket/bucket123"
        """#
      }
    }

    let options = BucketOptions(public: true)
    try await storage.updateBucket(
      "bucket123",
      options: options
    )
  }

  func testDeleteBucket() async throws {
    mockResponses = [
      (
        Data(),
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--request DELETE \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	"http://example.com/bucket/bucket123"
        """#
      }
    }

    try await storage.deleteBucket("bucket123")
  }

  func testEmptyBucket() async throws {
    mockResponses = [
      (
        Data(),
        HTTPURLResponse(
          url: URL(string: "http://example.com")!,
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
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	"http://example.com/bucket/bucket123/empty"
        """#
      }
    }

    try await storage.emptyBucket("bucket123")
  }
}
