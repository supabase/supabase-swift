import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Storage

extension StorageTests {
  final class StorageBucketApiTests {

    let api: SupabaseStorageClient

    init() {
      api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
    }

    deinit {
      Mocker.removeAll()
    }

    @Test
    func listBuckets_decodesResponse_andBuildsGETRequest() async throws {
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let buckets = try await api.listBuckets()

      let bucket = try #require(buckets.first)
      #expect(bucket.id == "bucket123")
      #expect(bucket.name == "test-bucket")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "GET")
      #expect(
        (request.value(forHTTPHeaderField: "X-Client-Info") ?? "").hasPrefix("storage-swift/"))
      #expect(request.url?.path.hasSuffix("/storage/v1/bucket") == true)
    }

    @Test
    func getBucket_decodesResponse_andBuildsGETRequest() async throws {
      let bucketId = "bucket123"
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: Data(
            """
            {
              "id": "bucket123",
              "name": "test-bucket",
              "owner": "owner123",
              "public": true,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """.utf8
          )
        ]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let bucket = try await api.getBucket(bucketId)

      #expect(bucket.id == "bucket123")
      #expect(bucket.isPublic == true)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path.hasSuffix("/storage/v1/bucket/\(bucketId)") == true)
    }

    @Test
    func createBucket_sendsPOSTWithSnakeCaseBody() async throws {
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data("{}".utf8)]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.createBucket(
        "newbucket",
        options: BucketOptions(
          public: true, fileSizeLimit: "5242880", allowedMimeTypes: ["image/jpeg"])
      )

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["id"] as? String == "newbucket")
      #expect(json["name"] as? String == "newbucket")
      #expect(json["public"] as? Bool == true)
      #expect(json["file_size_limit"] as? String == "5242880")
      #expect(json["allowed_mime_types"] as? [String] == ["image/jpeg"])
    }

    @Test
    func updateBucket_sendsPUTWithSnakeCaseBody() async throws {
      let bucketId = "bucket123"
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.put: Data("{}".utf8)]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.updateBucket(bucketId, options: BucketOptions(public: false))

      let request = try #require(captured.value)
      #expect(request.httpMethod == "PUT")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["id"] as? String == bucketId)
      #expect(json["name"] as? String == bucketId)
      #expect(json["public"] as? Bool == false)
    }

    @Test
    func emptyBucket_sendsPOST() async throws {
      let bucketId = "bucket123"
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket/\(bucketId)/empty"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.emptyBucket(bucketId)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path.hasSuffix("/storage/v1/bucket/\(bucketId)/empty") == true)
    }

    @Test
    func deleteBucket_sendsDELETE() async throws {
      let bucketId = "bucket123"
      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.delete: Data()]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.deleteBucket(bucketId)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "DELETE")
      #expect(request.url?.path.hasSuffix("/storage/v1/bucket/\(bucketId)") == true)
    }
  }
}
