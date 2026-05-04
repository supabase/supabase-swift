import Foundation
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct StorageBucketAPITests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let storage: StorageClient

  init() {
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

  @Test func urlConstruction() {
    let urlTestCases = [
      (
        input: "https://blah.supabase.co/storage/v1",
        expected: "https://blah.storage.supabase.co/storage/v1"
      ),
      (
        input: "https://blah.supabase.red/storage/v1",
        expected: "https://blah.storage.supabase.red/storage/v1"
      ),
      (
        input: "https://blah.storage.supabase.co/storage/v1",
        expected: "https://blah.storage.supabase.co/storage/v1"
      ),
      (
        input: "https://blah.supabase.co.example.com/storage/v1",
        expected: "https://blah.supabase.co.example.com/storage/v1"
      ),
      (
        input: "http://localhost:1234/storage/v1",
        expected: "http://localhost:1234/storage/v1"
      ),
    ]

    for testCase in urlTestCases {
      let storageWithNew = StorageClient(
        url: URL(string: testCase.input)!,
        configuration: StorageClientConfiguration(headers: [:], useNewHostname: true)
      )
      #expect(storageWithNew.url.absoluteString == testCase.expected)

      let storageWithout = StorageClient(
        url: URL(string: testCase.input)!,
        configuration: StorageClientConfiguration(headers: [:], useNewHostname: false)
      )
      #expect(storageWithout.url.absoluteString == testCase.input)
    }
  }

  @Test func getBucket() async throws {
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
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    let bucket = try await storage.getBucket("bucket123")
    #expect(bucket.id == "bucket123")
    #expect(bucket.name == "test-bucket")
  }

  @Test func listBuckets() async throws {
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
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }
    .register()

    let buckets = try await storage.listBuckets()
    #expect(buckets.count == 1)
    #expect(buckets[0].name == "test-bucket")
  }

  @Test func createBucket() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }
    .register()

    let options = BucketOptions(isPublic: true)
    try await storage.createBucket(
      "newbucket",
      options: options
    )
  }

  @Test func updateBucket() async throws {
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
      	--header "Accept: application/json" \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":\"bucket123\",\"name\":\"bucket123\",\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    let options = BucketOptions(isPublic: true)
    try await storage.updateBucket(
      "bucket123",
      options: options
    )
  }

  @Test func deleteBucket() async throws {
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
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }
    .register()

    try await storage.deleteBucket("bucket123")
  }

  @Test func emptyBucket() async throws {
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
      	--header "Accept: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123/empty"
      """#
    }
    .register()

    try await storage.emptyBucket("bucket123")
  }
}
