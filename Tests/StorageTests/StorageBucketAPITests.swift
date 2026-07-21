import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shared serialization boundary for the Mocker-backed Storage test suites (this one and
/// ``StorageFileAPITests``): Mocker's mock registry is process-global, so these suites can't just
/// serialize their own tests internally, they must never run concurrently *with each other* either
/// -- otherwise one suite's `Mocker.removeAll()` (see `makeSUT()`) can wipe out mocks the other
/// suite just registered. `.serialized` on a suite applies recursively to its nested suites, so
/// nesting both under this empty namespace enforces that.
@Suite(.serialized)
enum StorageMockerTests {}

extension StorageMockerTests {
  struct StorageBucketAPITests {
    let url = URL(string: "http://localhost:54321/storage/v1")!

    init() {
      JSONEncoder.defaultStorageEncoder.outputFormatting = [
        .sortedKeys
      ]
    }

    private func makeSUT() -> SupabaseStorageClient {
      Mocker.removeAll()

      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: configuration)

      return SupabaseStorageClient(
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

    @Test(
      arguments: [
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
    )
    func urlConstructionWithNewHostname(input: String, expected: String, description: String) {
      let storage = SupabaseStorageClient(
        configuration: StorageClientConfiguration(
          url: URL(string: input)!,
          headers: [:],
          useNewHostname: true
        )
      )
      #expect(
        storage.configuration.url.absoluteString == expected,
        "should \(description) if useNewHostname is true"
      )
    }

    @Test(
      arguments: [
        "https://blah.supabase.co/storage/v1",
        "https://blah.supabase.red/storage/v1",
        "https://blah.storage.supabase.co/storage/v1",
        "https://blah.supabase.co.example.com/storage/v1",
        "http://localhost:1234/storage/v1",
      ]
    )
    func urlConstructionWithoutNewHostname(input: String) {
      let storage = SupabaseStorageClient(
        configuration: StorageClientConfiguration(
          url: URL(string: input)!,
          headers: [:],
          useNewHostname: false
        )
      )
      #expect(storage.configuration.url.absoluteString == input)
    }

    @Test
    func getBucket() async throws {
      let storage = makeSUT()

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
      #expect(bucket.id == "bucket123")
      #expect(bucket.name == "test-bucket")
    }

    @Test
    func listBuckets() async throws {
      let storage = makeSUT()

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
      #expect(buckets.count == 1)
      #expect(buckets[0].name == "test-bucket")
    }

    @Test
    func createBucket() async throws {
      let storage = makeSUT()

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

    @Test
    func updateBucket() async throws {
      let storage = makeSUT()

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

    @Test
    func deleteBucket() async throws {
      let storage = makeSUT()

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

    @Test
    func emptyBucket() async throws {
      let storage = makeSUT()

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

    @Test
    func createBucketWithFileSizeLimit() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("bucket"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "newbucket",
              "name": "newbucket",
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
        	--request POST \
        	--header "Content-Length: 79" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"file_size_limit\":10485760,\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":false}" \
        	"http://localhost:54321/storage/v1/bucket"
        """#
      }
      .register()

      try await storage.createBucket(
        "newbucket",
        options: BucketOptions(isPublic: false, fileSizeLimit: 10_485_760)
      )
    }

    @Test
    func createBucketWithHumanReadableFileSizeLimit() async throws {
      let storage = makeSUT()

      Mock(
        url: url.appendingPathComponent("bucket"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "newbucket",
              "name": "newbucket",
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
        	--request POST \
        	--header "Content-Length: 76" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: storage-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"file_size_limit\":\"1mb\",\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":false}" \
        	"http://localhost:54321/storage/v1/bucket"
        """#
      }
      .register()

      try await storage.createBucket(
        "newbucket",
        options: BucketOptions(isPublic: false, fileSizeLimit: "1mb")
      )
    }
  }
}
