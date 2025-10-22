import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class StorageBucketAPITests: XCTestCase {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  var storage: SupabaseStorageClient!

  override func setUp() {
    super.setUp()

    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockingURLProtocol.self]

    let session = URLSession(configuration: configuration)

    JSONEncoder.defaultStorageEncoder.outputFormatting = [
      .sortedKeys
    ]

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

  override func tearDown() {
    super.tearDown()

    Mocker.removeAll()
  }

  func testURLConstruction() async {
    let urlTestCases = [
      (
        "https://blah.supabase.co/storage/v1",
        "https://blah.storage.supabase.co/storage/v1",
        "update legacy prod host to new host"
      ),
      (
        "https://blah.supabase.red/storage/v1",
        "https://blah.storage.supabase.red/storage/v1",
        "update legacy staging host to new host"
      ),
      (
        "https://blah.storage.supabase.co/storage/v1",
        "https://blah.storage.supabase.co/storage/v1",
        "accept new host without modification"
      ),
      (
        "https://blah.supabase.co.example.com/storage/v1",
        "https://blah.supabase.co.example.com/storage/v1",
        "not modify non-platform hosts"
      ),
      (
        "http://localhost:1234/storage/v1",
        "http://localhost:1234/storage/v1",
        "support local host with port without modification"
      ),
    ]

    for (input, expect, description) in urlTestCases {
      await XCTContext.runActivity(named: "should \(description) if useNewHostname is true") { _ in
        let storage = SupabaseStorageClient(
          configuration: StorageClientConfiguration(
            url: URL(string: input)!,
            headers: [:],
            useNewHostname: true
          )
        )
        XCTAssertEqual(storage.configuration.url.absoluteString, expect)
      }

      await XCTContext.runActivity(named: "should not modify host if useNewHostname is false") { _ in
        let storage = SupabaseStorageClient(
          configuration: StorageClientConfiguration(
            url: URL(string: input)!,
            headers: [:],
            useNewHostname: false
          )
        )
        XCTAssertEqual(storage.configuration.url.absoluteString, input)
      }
    }
  }

  func testGetBucket() async throws {
    Mock(
      url: url.appendingPathComponent("bucket/bucket123"),
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
              "id": "bucket123",
              "name": "test-bucket",
              "owner": "owner123",
              "public": false,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
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
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    let bucket = try await storage.getBucket("bucket123")
    XCTAssertEqual(bucket.id, "bucket123")
    XCTAssertEqual(bucket.name, "test-bucket")
  }

  func testListBuckets() async throws {
    Mock(
      url: url.appendingPathComponent("bucket"),
      statusCode: 200,
      data: [
        .get: Data(
          """
          [
            {
              "id": "bucket123",
              "name": "test-bucket",
              "owner": "owner123",
              "public": false,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
          ]
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }
    .register()

    let buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets.count, 1)
    XCTAssertEqual(buckets[0].name, "test-bucket")
  }

  func testCreateBucket() async throws {
    Mock(
      url: url.appendingPathComponent("bucket"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "newbucket",
            "name": "new-bucket",
            "owner": "owner123",
            "public": true,
            "created_at": "2024-01-01T00:00:00.000Z",
            "updated_at": "2024-01-01T00:00:00.000Z"
          }
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
      	--data "{\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }
    .register()

    let options = BucketOptions(public: true)
    try await storage.createBucket(
      "newbucket",
      options: options
    )
  }

  func testUpdateBucket() async throws {
    Mock(
      url: url.appendingPathComponent("bucket/bucket123"),
      statusCode: 200,
      data: [
        .put: Data(
          """
          {
            "id": "bucket123",
            "name": "updated-bucket",
            "owner": "owner123",
            "public": true,
            "created_at": "2024-01-01T00:00:00.000Z",
            "updated_at": "2024-01-01T00:00:00.000Z"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":\"bucket123\",\"name\":\"bucket123\",\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    let options = BucketOptions(public: true)
    try await storage.updateBucket(
      "bucket123",
      options: options
    )
  }

  func testDeleteBucket() async throws {
    Mock(
      url: url.appendingPathComponent("bucket/bucket123"),
      statusCode: 200,
      data: [
        .delete: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    try await storage.deleteBucket("bucket123")
  }

  func testEmptyBucket() async throws {
    Mock(
      url: url.appendingPathComponent("bucket/bucket123/empty"),
      statusCode: 200,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123/empty"
      """#
    }
    .register()

    try await storage.emptyBucket("bucket123")
  }
}
