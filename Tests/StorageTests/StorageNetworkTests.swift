import ConcurrencyExtras
import Foundation
import HTTPTypes
import Mocker
import Testing

@testable import Storage

extension StorageTests {
  final class StorageNetworkTests {

    deinit {
      Mocker.removeAll()
    }

    // MARK: StorageApi

    @Test
    func init_setsDefaultXClientInfoHeaderIfMissing() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: ["X-Foo": "bar"],
          session: StorageTestSupport.makeSession()
        )
      )

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.execute(
        url: api.configuration.url.appendingPathComponent("bucket"), method: .get)

      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "X-Foo") == "bar")
      #expect(
        (request.value(forHTTPHeaderField: "X-Client-Info") ?? "").hasPrefix("storage-swift/"))
    }

    @Test
    func init_doesNotOverrideProvidedXClientInfo() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: ["X-Client-Info": "my-client/1.0"],
          session: StorageTestSupport.makeSession()
        )
      )

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.execute(
        url: api.configuration.url.appendingPathComponent("bucket"), method: .get)

      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "X-Client-Info") == "my-client/1.0")
    }

    @Test
    func init_rewritesLegacySupabaseHostWhenUseNewHostnameTrue() {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: URL(string: "https://project-ref.supabase.co/storage/v1")!,
          headers: [:],
          session: StorageTestSupport.makeSession(),
          useNewHostname: true
        )
      )

      #expect(
        api.configuration.url.absoluteString == "https://project-ref.storage.supabase.co/storage/v1"
      )
    }

    @Test
    func executeStream_setsJSONContentTypeWhenBodyProvidedAndMissing() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: [:],
          session: StorageTestSupport.makeSession()
        )
      )

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data("{}".utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.executeStream(
        url: api.configuration.url.appendingPathComponent("bucket"),
        method: .post,
        body: HTTPBody(Data("{}".utf8))
      )

      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func accessTokenMiddleware_setsAuthorizationHeader() async throws {
      let tokenCalls = LockIsolated(0)
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: [:],
          session: StorageTestSupport.makeSession(),
          accessToken: {
            tokenCalls.withValue { $0 += 1 }
            return "access.token"
          }
        )
      )

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.execute(
        url: api.configuration.url.appendingPathComponent("bucket"), method: .get)

      #expect(tokenCalls.value == 1)
      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access.token")
    }

    @Test
    func execute_non2xx_decodesStorageErrorWhenPossible() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: [:],
          session: StorageTestSupport.makeSession()
        )
      )

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 400,
        data: [
          .get: Data(#"{"statusCode":"400","message":"Bad request","error":"BadRequest"}"#.utf8)
        ]
      ).register()

      do {
        _ = try await api.execute(
          url: api.configuration.url.appendingPathComponent("bucket"), method: .get)
        Issue.record("Expected StorageError")
      } catch let error as StorageError {
        #expect(error.statusCode == "400")
        #expect(error.message == "Bad request")
        #expect(error.error == "BadRequest")
      }
    }

    @Test
    func execute_non2xx_throwsStorageHTTPErrorWhenBodyIsNotStorageErrorJSON() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: [:],
          session: StorageTestSupport.makeSession()
        )
      )

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("bucket"),
        ignoreQuery: true,
        statusCode: 500,
        data: [.get: Data("nope".utf8)]
      ).register()

      do {
        _ = try await api.execute(
          url: api.configuration.url.appendingPathComponent("bucket"), method: .get)
        Issue.record("Expected StorageHTTPError")
      } catch let error as StorageHTTPError {
        #expect(error.response.status.code == 500)
        #expect(String(decoding: error.data, as: UTF8.self) == "nope")
      }
    }

    @Test
    func buildRequest_mergesQueryFromURLAndParameters_andNormalizesDuplicates() async throws {
      let api = StorageApi(
        configuration: StorageClientConfiguration(
          url: StorageTestSupport.baseURL,
          headers: [:],
          session: StorageTestSupport.makeSession()
        )
      )

      let captured = LockIsolated<URLRequest?>(nil)
      let urlWithQuery = api.configuration.url
        .appendingPathComponent("object")
        .appendingQueryItems([
          URLQueryItem(name: "a", value: "1"), URLQueryItem(name: "dup", value: "old"),
        ])

      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data()]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.execute(
        url: urlWithQuery,
        method: .get,
        query: [URLQueryItem(name: "dup", value: "new"), URLQueryItem(name: "b", value: "2")]
      )

      let request = try #require(captured.value)
      let query = try StorageTestSupport.queryDictionary(request)
      #expect(query["a"] == "1")
      #expect(query["b"] == "2")
      #expect(query["dup"] == "new")
    }

    // MARK: StorageBucketApi

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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
      let buckets = try await api.listBuckets()
      let bucket = try #require(buckets.first)

      #expect(buckets.count == 1)
      #expect(bucket.id == "bucket123")
      #expect(bucket.name == "test-bucket")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "GET")
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
      try await api.createBucket(
        "newbucket",
        options: BucketOptions(
          public: true, fileSizeLimit: "5242880", allowedMimeTypes: ["image/jpeg"])
      )

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

      let body = try #require(StorageTestSupport.requestBody(request))
      let json = try #require(StorageTestSupport.jsonObject(body) as? [String: Any])
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
      try await api.updateBucket(bucketId, options: BucketOptions(public: false))

      let request = try #require(captured.value)
      #expect(request.httpMethod == "PUT")

      let body = try #require(StorageTestSupport.requestBody(request))
      let json = try #require(StorageTestSupport.jsonObject(body) as? [String: Any])
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let api = StorageTestSupport.makeClient(headers: ["apikey": "anon"])
      try await api.deleteBucket(bucketId)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "DELETE")
      #expect(request.url?.path.hasSuffix("/storage/v1/bucket/\(bucketId)") == true)
    }

    // MARK: StorageFileApi (subset)

    @Test
    func file_list_buildsPOSTBodyWithDefaultOptions() async throws {

      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/list/\(bucketId)"),
        ignoreQuery: true,
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
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let files = try await api.list(path: "folder")
      #expect(files.count == 1)

      let request = try #require(captured.value)
      let body = try #require(StorageTestSupport.requestBody(request))
      let json = try #require(StorageTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["prefix"] as? String == "folder")
    }

    @Test
    func file_move_sendsPOSTWithExpectedJSONBody() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/move"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.move(from: "old/path.txt", to: "new/path.txt")

      let request = try #require(captured.value)
      let body = try #require(StorageTestSupport.requestBody(request))
      let json = try #require(StorageTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["bucketId"] as? String == bucketId)
      #expect(json["sourceKey"] as? String == "old/path.txt")
      #expect(json["destinationKey"] as? String == "new/path.txt")

    }

    @Test
    func file_copy_returnsKey() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/copy"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"Key":"object/dest/file.txt"}"#.utf8)]
      ).register()

      let key = try await api.copy(from: "source/file.txt", to: "dest/file.txt")
      #expect(key == "object/dest/file.txt")

    }

    @Test
    func file_createSignedURL_addsDownloadQueryItem() async throws {

      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/sign/\(bucketId)/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"signedURL":"/sign/file.txt?token=abc.def"}"#.utf8)]
      ).register()

      let url = try await api.createSignedURL(path: "file.txt", expiresIn: 60, download: "name.txt")
      #expect(url.absoluteString.contains("/storage/v1/sign/file.txt?token=abc.def") == true)
      #expect(url.absoluteString.contains("download=name.txt") == true)

    }

    @Test
    func file_createSignedURLs_buildsExpectedURLs() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/sign/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .post: Data(
            """
            [
              { "signedURL": "/sign/file1.txt?token=abc" },
              { "signedURL": "/sign/file2.txt?token=abc" }
            ]
            """.utf8
          )
        ]
      ).register()

      let urls = try await api.createSignedURLs(paths: ["file1.txt", "file2.txt"], expiresIn: 60)
      #expect(urls.count == 2)
      #expect(urls[0].absoluteString.contains("/storage/v1/sign/file1.txt?token=abc") == true)
      #expect(urls[1].absoluteString.contains("/storage/v1/sign/file2.txt?token=abc") == true)
    }

    @Test
    func file_remove_sendsDELETEWithPrefixesBody() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.delete: Data("[]".utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.remove(paths: ["a.txt", "b.txt"])

      let request = try #require(captured.value)
      let body = try #require(StorageTestSupport.requestBody(request))
      let json = try #require(StorageTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["prefixes"] as? [String] == ["a.txt", "b.txt"])
    }

    @Test
    func file_download_usesRenderPathAndQueryItemsWhenTransformOptionsProvided() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent(
          "render/image/authenticated/\(bucketId)/file.png"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data([0x01, 0x02])]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let data = try await api.download(
        path: "file.png", options: TransformOptions(width: 10, height: 20, quality: 75))
      #expect(data == Data([0x01, 0x02]))

      let request = try #require(captured.value)
      let query = try StorageTestSupport.queryDictionary(request)
      #expect(query["width"] == "10")
      #expect(query["height"] == "20")
      #expect(query["quality"] == "75")
    }

    @Test
    func file_exists_returnsTrueOnSuccess_andFalseOn404() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/\(bucketId)/exists.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.head: Data()]
      ).register()

      let exists = try await api.exists(path: "exists.txt")
      #expect(exists == true)

      Mocker.removeAll()

      Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/\(bucketId)/missing.txt"),
        ignoreQuery: true,
        statusCode: 404,
        data: [.head: Data("missing".utf8)]
      ).register()

      let missingExists = try await api.exists(path: "missing.txt")
      #expect(missingExists == false)
    }

    @Test
    func file_getPublicURL_buildsExpectedURL() throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let base = try api.getPublicURL(path: "README.md")
      #expect(
        base.absoluteString
          == "https://example.supabase.co/storage/v1/object/public/\(bucketId)/README.md")
    }

    @Test
    func file_createSignedUploadURL_parsesToken_andSetsXUpsertHeaderWhenEnabled() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent(
          "object/upload/sign/\(bucketId)/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"url":"/object/upload/sign/bucket/file.txt?token=tok"}"#.utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let result = try await api.createSignedUploadURL(
        path: "file.txt", options: .init(upsert: true))
      #expect(result.token == "tok")

      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "x-upsert") == "true")
    }

    @Test
    func file_uploadToSignedURL_sendsPUTWithTokenQuery_andReturnsFullPath() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      #if DEBUG
        testingBoundary.setValue("test.boundary")
      #endif

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent(
          "object/upload/sign/\(bucketId)/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.put: Data(#"{"Key":"bucket/file.txt"}"#.utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let response = try await api.uploadToSignedURL(
        "file.txt", token: "tok", data: Data("hello".utf8))
      #expect(response.fullPath == "bucket/file.txt")

      let request = try #require(captured.value)
      let query = try StorageTestSupport.queryDictionary(request)
      #expect(query["token"] == "tok")
    }

    @Test
    func file_upload_trimsPath_andSetsHeaders() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      #if DEBUG
        testingBoundary.setValue("test.boundary")
      #endif

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent(
          "object/\(bucketId)/folder/file1.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"Id":"id","Key":"bucket/folder/file1.txt"}"#.utf8)]
      )
      mock.onRequestHandler = StorageTestSupport.captureRequest(into: captured)
      mock.register()

      let result = try await api.upload(
        "//folder//file1.txt//",
        data: Data("test data".utf8),
        options: FileOptions(cacheControl: "14400", upsert: false, metadata: ["k": .string("v")])
      )
      #expect(result.fullPath == "bucket/folder/file1.txt")

      let request = try #require(captured.value)
      #expect(request.value(forHTTPHeaderField: "x-upsert") == "false")
      #expect(request.value(forHTTPHeaderField: "Cache-Control") == "max-age=14400")
    }
  }
}
