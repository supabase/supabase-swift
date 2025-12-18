import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Storage

extension StorageTests {
  final class StorageFileApiTests {

    deinit {
      Mocker.removeAll()
    }

    @Test
    func list_buildsPOSTBodyWithDefaultOptions() async throws {
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let files = try await api.list(path: "folder")
      #expect(files.count == 1)
      #expect(files[0].name == "test.txt")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["prefix"] as? String == "folder")
      #expect(json["limit"] as? Int == 100)
      #expect(json["offset"] as? Int == 0)
      let sortBy = json["sortBy"] as? [String: Any]
      #expect(sortBy?["column"] as? String == "name")
      #expect(sortBy?["order"] as? String == "asc")
    }

    @Test
    func move_sendsPOSTWithExpectedJSONBody() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/move"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      try await api.move(from: "old/path.txt", to: "new/path.txt")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["bucketId"] as? String == bucketId)
      #expect(json["sourceKey"] as? String == "old/path.txt")
      #expect(json["destinationKey"] as? String == "new/path.txt")
      #expect(json["destinationBucket"] == nil || json["destinationBucket"] is NSNull)
    }

    @Test
    func copy_returnsKey_andSendsPOSTWithExpectedJSONBody() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/copy"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"Key":"object/dest/file.txt"}"#.utf8)]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let key = try await api.copy(from: "source/file.txt", to: "dest/file.txt")
      #expect(key == "object/dest/file.txt")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["bucketId"] as? String == bucketId)
      #expect(json["sourceKey"] as? String == "source/file.txt")
      #expect(json["destinationKey"] as? String == "dest/file.txt")
    }

    @Test
    func createSignedURL_buildsExpectedURL_andCanAddDownloadQueryItem() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/sign/\(bucketId)/file.txt"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"signedURL":"/sign/file.txt?token=abc.def"}"#.utf8)]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let url = try await api.createSignedURL(path: "file.txt", expiresIn: 60, download: "name.txt")
      #expect(url.absoluteString.contains("/storage/v1/sign/file.txt?token=abc.def") == true)
      #expect(url.absoluteString.contains("download=name.txt") == true)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["expiresIn"] as? Int == 60)
    }

    @Test
    func createSignedURLs_buildsExpectedURLs() async throws {
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
    func remove_sendsDELETEWithPrefixesBody() async throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let captured = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: StorageTestSupport.baseURL.appendingPathComponent("object/\(bucketId)"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.delete: Data("[]".utf8)]
      )
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      _ = try await api.remove(paths: ["a.txt", "b.txt"])

      let request = try #require(captured.value)
      #expect(request.httpMethod == "DELETE")

      let body = try #require(HTTPTestSupport.requestBody(request))
      let json = try #require(HTTPTestSupport.jsonObject(body) as? [String: Any])
      #expect(json["prefixes"] as? [String] == ["a.txt", "b.txt"])
    }

    @Test
    func download_usesRenderPathAndQueryItemsWhenTransformOptionsProvided() async throws {
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let data = try await api.download(
        path: "file.png", options: TransformOptions(width: 10, height: 20, quality: 75))
      #expect(data == Data([0x01, 0x02]))

      let request = try #require(captured.value)
      let query = try HTTPTestSupport.queryDictionary(request)
      #expect(query["width"] == "10")
      #expect(query["height"] == "20")
      #expect(query["quality"] == "75")
    }

    @Test
    func exists_returnsTrueOnSuccess_andFalseOn404() async throws {
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
    func getPublicURL_buildsExpectedURLsWithDownloadAndTransformOptions() throws {
      let bucketId = "bucket"
      let api = StorageTestSupport.makeFileAPI(bucketId: bucketId, headers: ["apikey": "anon"])

      let base = try api.getPublicURL(path: "README.md")
      #expect(
        base.absoluteString
          == "https://example.supabase.co/storage/v1/object/public/\(bucketId)/README.md")

      let withDownload = try api.getPublicURL(path: "README.md", download: true)
      #expect(withDownload.absoluteString.contains("download=") == true)

      let withTransform = try api.getPublicURL(
        path: "README.md",
        download: "file",
        options: TransformOptions(width: 300, height: 300)
      )
      #expect(
        withTransform.absoluteString.contains(
          "/storage/v1/render/image/public/\(bucketId)/README.md")
          == true)
      #expect(withTransform.absoluteString.contains("download=file") == true)
      #expect(withTransform.absoluteString.contains("width=300") == true)
      #expect(withTransform.absoluteString.contains("height=300") == true)
      #expect(withTransform.absoluteString.contains("quality=80") == true)
    }

    @Test
    func createSignedUploadURL_parsesToken_andSetsXUpsertHeaderWhenEnabled() async throws {
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let result = try await api.createSignedUploadURL(
        path: "file.txt", options: .init(upsert: true))
      #expect(result.path == "file.txt")
      #expect(result.token == "tok")
      #expect(result.signedURL.absoluteString.contains("token=tok") == true)

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "x-upsert") == "true")
    }

    @Test
    func uploadToSignedURL_sendsPUTWithTokenQuery_andReturnsFullPath() async throws {
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let response = try await api.uploadToSignedURL(
        "file.txt", token: "tok", data: Data("hello".utf8))
      #expect(response.fullPath == "bucket/file.txt")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "PUT")
      let query = try HTTPTestSupport.queryDictionary(request)
      #expect(query["token"] == "tok")

      let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
      #expect(contentType.contains("multipart/form-data") == true)
    }

    @Test
    func upload_trimsPath_andSetsHeaders() async throws {
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
      mock.onRequestHandler = HTTPTestSupport.captureRequest(into: captured)
      mock.register()

      let result = try await api.upload(
        "//folder//file1.txt//",
        data: Data("test data".utf8),
        options: FileOptions(cacheControl: "14400", upsert: false, metadata: ["k": .string("v")])
      )

      #expect(result.path == "//folder//file1.txt//")
      #expect(result.fullPath == "bucket/folder/file1.txt")

      let request = try #require(captured.value)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "x-upsert") == "false")
      #expect(request.value(forHTTPHeaderField: "Cache-Control") == "max-age=14400")
    }
  }
}
