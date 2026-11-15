import Foundation
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageClientBucketsTests {
  let url = URL(string: "http://localhost:54321/storage/v1")!
  let transport = RecordingTransport()

  private func makeSUT() throws -> StorageClient {
    try StorageClient(
      configuration: StorageClient.Configuration(
        url: url,
        headers: [
          .apikey:
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        http: .init(transport: transport))
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
      (
        "https://blah.supabasexco/storage/v1",
        "https://blah.supabasexco/storage/v1",
        "not treat a non-dot separator as a platform host"
      ),
      (
        "https://supabase.co/storage/v1",
        "https://supabase.co/storage/v1",
        "not rewrite the bare apex domain, which is not a project host"
      ),
      (
        "https://not-supabase.co/storage/v1",
        "https://not-supabase.co/storage/v1",
        "not rewrite a host that only ends with the apex, without a label boundary"
      ),
      (
        "https://mysupabase.in/storage/v1",
        "https://mysupabase.in/storage/v1",
        "not rewrite a caller-owned domain ending in the apex"
      ),
    ]
  )
  func urlConstructionWithNewHostname(input: String, expected: String, description: String) throws {
    let storage = try StorageClient(
      configuration: StorageClient.Configuration(
        url: URL(string: input)!,
        headers: [:],
        usesNewHostname: true
      )
    )
    #expect(
      storage.configuration.url.absoluteString == expected,
      "should \(description) if usesNewHostname is true"
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
  func urlConstructionWithoutNewHostname(input: String) throws {
    let storage = try StorageClient(
      configuration: StorageClient.Configuration(
        url: URL(string: input)!,
        headers: [:],
        usesNewHostname: false
      )
    )
    #expect(storage.configuration.url.absoluteString == input)
  }

  @Test
  func bucket() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("bucket/bucket123"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }

    let bucket = try await storage.bucket("bucket123")
    #expect(bucket.id == "bucket123")
    #expect(bucket.name == "test-bucket")
  }

  @Test
  func listBuckets() async throws {
    let storage = try makeSUT()

    transport.stub(
      .get,
      url.appendingPathComponent("bucket"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }

    let buckets = try await storage.listBuckets()
    #expect(buckets.count == 1)
    #expect(buckets[0].name == "test-bucket")
  }

  @Test
  func createBucket() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("bucket"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 51" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }

    let options = CreateBucketOptions(isPublic: true)
    let name = try await storage.createBucket(
      "newbucket",
      options: options
    )

    #expect(name == "new-bucket")
  }

  @Test
  func updateBucketSendsOnlyTheFieldsThatAreSet() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("bucket/bucket123"),
      data: Data(#"{"message":"Successfully updated"}"#.utf8)
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Content-Length: 37" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"allowed_mime_types\":[\"image\/png\"]}" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }

    try await storage.updateBucket(
      "bucket123", options: UpdateBucketOptions(allowedMimeTypes: ["image/png"]))
  }

  @Test
  func updateBucketWithNothingToChangeThrowsBeforeSending() async throws {
    let storage = try makeSUT()

    await #expect {
      try await storage.updateBucket("bucket123", options: UpdateBucketOptions())
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
  }

  @Test
  func updateBucket() async throws {
    let storage = try makeSUT()

    transport.stub(
      .put,
      url.appendingPathComponent("bucket/bucket123"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Content-Length: 15" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"public\":true}" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }

    let options = UpdateBucketOptions(isPublic: true)
    try await storage.updateBucket(
      "bucket123",
      options: options
    )
  }

  @Test
  func deleteBucket() async throws {
    let storage = try makeSUT()

    transport.stub(.delete, url.appendingPathComponent("bucket/bucket123")) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123"
      """#
    }

    try await storage.deleteBucket("bucket123")
  }

  @Test
  func emptyBucket() async throws {
    let storage = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("bucket/bucket123/empty")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/bucket/bucket123/empty"
      """#
    }

    try await storage.emptyBucket("bucket123")
  }

  @Test
  func purgeCacheForBucket() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("cdn/bucket123"),
      data: Data(#"{"message":"success"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/cdn/bucket123"
      """#
    }

    try await storage.purgeCache(bucket: "bucket123")
  }

  @Test
  func purgeCacheForBucketTransformationsOnly() async throws {
    let storage = try makeSUT()

    transport.stub(
      .delete,
      url.appendingPathComponent("cdn/bucket123"),
      data: Data(#"{"message":"success"}"#.utf8)
    ) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/storage/v1/cdn/bucket123?transformations=true"
      """#
    }

    try await storage.purgeCache(bucket: "bucket123", transformationsOnly: true)
  }

  @Test
  func createBucketWithFileSizeLimit() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("bucket"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 79" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"file_size_limit\":10485760,\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":false}" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }

    try await storage.createBucket(
      "newbucket",
      options: CreateBucketOptions(isPublic: false, fileSizeLimit: 10_485_760)
    )
  }

  @Test
  func createBucketWithHumanReadableFileSizeLimit() async throws {
    let storage = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("bucket"),
      data: Data(
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
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 76" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"file_size_limit\":\"1mb\",\"id\":\"newbucket\",\"name\":\"newbucket\",\"public\":false}" \
      	"http://localhost:54321/storage/v1/bucket"
      """#
    }

    try await storage.createBucket(
      "newbucket",
      options: CreateBucketOptions(isPublic: false, fileSizeLimit: .megabytes(1))
    )
  }
}
