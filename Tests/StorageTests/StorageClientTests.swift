import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing
import IssueReporting

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageClientTests {
  let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketID = "tests"

  @Test
  func publicURL() throws {
    let sut = try makeSUT()

    let path = "README.md"

    let baseUrl = sut.from(bucketID).publicURL(path: path)
    #expect(baseUrl.absoluteString == "\(supabaseURL)/object/public/\(bucketID)/\(path)")

    let baseUrlWithDownload = sut.from(bucketID).publicURL(
      path: path, options: PublicURLOptions(download: .withOriginalName))
    assertInlineSnapshot(of: baseUrlWithDownload, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=
      """
    }

    let baseUrlWithDownloadAndFileName = sut.from(bucketID).publicURL(
      path: path, options: PublicURLOptions(download: .named("test")))
    assertInlineSnapshot(of: baseUrlWithDownloadAndFileName, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=test
      """
    }

    let baseUrlWithAllOptions = sut.from(bucketID).publicURL(
      path: path,
      options: PublicURLOptions(
        download: .named("test"), transform: ImageTransform(width: 300, height: 300)))
    assertInlineSnapshot(of: baseUrlWithAllOptions, as: .description) {
      """
      http://localhost:54321/storage/v1/render/image/public/tests/README.md?download=test&width=300&height=300
      """
    }
  }

  @Test
  func createSignedURLs() async throws {
    let sut = try makeSUT(fetch: { _ in
      (
        """
        [
          {
            "path": "file1.txt",
            "signedURL": "/sign/file1.txt?token=abc.def.ghi"
          },
          {
            "path": "file2.txt",
            "signedURL": "/sign/file2.txt?token=abc.def.ghi"
          }
        ]
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })
    let results: [SignedURLResult] = try await sut.from(bucketID).createSignedURLs(
      paths: ["file1.txt", "file2.txt"],
      expiresIn: .seconds(60)
    )

    #expect(results.count == 2)
    guard case .success(let path0, let url0) = results[0] else {
      Issue.record("Expected success for file1.txt")
      return
    }
    #expect(path0 == "file1.txt")
    #expect(
      url0.absoluteString
        == "http://localhost:54321/storage/v1/sign/file1.txt?token=abc.def.ghi")
    guard case .success(let path1, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(path1 == "file2.txt")
    #expect(
      url1.absoluteString
        == "http://localhost:54321/storage/v1/sign/file2.txt?token=abc.def.ghi")
  }

  @Test
  func uploadData() async throws {
    let sut = try makeSUT(fetch: { request in
      assertInlineSnapshot(of: request, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer test.api.key" \
        	--header "Cache-Control: max-age=14400" \
        	--header "Content-Type: text/plain" \
        	--header "X-Client-Info: storage-swift/x.y.z" \
        	--header "apikey: test.api.key" \
        	--header "x-metadata: eyJrZXkiOiJ2YWx1ZSJ9" \
        	--header "x-upsert: false" \
        	--data "test data" \
        	"http://localhost:54321/storage/v1/object/tests/file1.txt"
        """#
      }
      return (
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "tests/file1.txt"
        }
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    try await sut.from(bucketID)
      .upload(
        path: "file1.txt",
        data: "test data".data(using: .utf8)!,
        options: UploadOptions(
          cacheControl: .maxAge(.seconds(14400)),
          metadata: ["key": "value"]
        )
      )
  }

  @Test
  func uploadFileURL() async throws {
    let sut = try makeSUT(fetch: { request in
      assertInlineSnapshot(of: request, as: .curl) {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer test.api.key" \
        	--header "Cache-Control: max-age=3600" \
        	--header "Content-Type: image/jpeg" \
        	--header "X-Client-Info: storage-swift/x.y.z" \
        	--header "apikey: test.api.key" \
        	--header "x-metadata: eyJrZXkiOiJ2YWx1ZSJ9" \
        	--header "x-upsert: false" \
        	"http://localhost:54321/storage/v1/object/tests/sadcat.jpg"
        """#
      }
      return (
        """
        {
          "Id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "Key": "tests/file1.txt"
        }
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    try await sut.from(bucketID)
      .upload(
        path: "sadcat.jpg",
        fileURL: uploadFileURL("sadcat.jpg"),
        options: UploadOptions(
          metadata: ["key": "value"]
        )
      )
  }

  private func makeSUT(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = unimplemented(
      "makeSUT.fetch")
  ) throws -> StorageClient {
    try StorageClient.test(
      supabaseURL: supabaseURL.absoluteString,
      apiKey: "test.api.key",
      http: .init(
        transport: ClosureTransport { request, body in
          guard var urlRequest = URLRequest(httpRequest: request) else { throw URLError(.badURL) }
          if let body { urlRequest.httpBody = try await Data(collecting: body, upTo: .max) }
          let (data, response) = try await fetch(urlRequest)
          guard let head = (response as? HTTPURLResponse)?.httpResponse else {
            throw URLError(.badServerResponse)
          }
          return (head, data.isEmpty ? nil : HTTPBody(data))
        }))
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent(fileName)
  }

  @Test
  func settingHeader_setsHeaderOnRequest() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sut = try makeSUT(fetch: { request in
      capturedRequest.setValue(request)
      return (
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
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await sut.from(bucketID)
      .settingHeader(name: .init("X-Custom-Header")!, value: "custom-value")
      .list()

    #expect(
      capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
  }

  @Test
  func settingHeader_supportsMethodChaining() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sut = try makeSUT(fetch: { request in
      capturedRequest.setValue(request)
      return (
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
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await sut.from(bucketID)
      .settingHeader(name: .init("X-Header-A")!, value: "value-a")
      .settingHeader(name: .init("X-Header-B")!, value: "value-b")
      .list()

    #expect(capturedRequest.value?.value(forHTTPHeaderField: "X-Header-A") == "value-a")
    #expect(capturedRequest.value?.value(forHTTPHeaderField: "X-Header-B") == "value-b")
  }

  @Test
  func settingHeader_overridesExistingHeader() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sut = try makeSUT(fetch: { request in
      capturedRequest.setValue(request)
      return (
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
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await sut.from(bucketID)
      .settingHeader(name: .init("X-Custom-Header")!, value: "initial-value")
      .settingHeader(name: .init("X-Custom-Header")!, value: "updated-value")
      .list()

    #expect(
      capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header") == "updated-value")
  }

  @Test
  func settingHeader_doesNotMutateParentClientHeaders() async throws {
    let capturedRequests = LockIsolated<[URLRequest]>([])

    let listResponse = """
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
      """

    let sut = try makeSUT(fetch: { request in
      capturedRequests.withValue { $0.append(request) }

      return (
        listResponse.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await sut.from(bucketID)
      .settingHeader(name: .init("X-Child-Header")!, value: "child-value")
      .list()

    #expect(
      capturedRequests[0].value(forHTTPHeaderField: "X-Child-Header")
        == "child-value"
    )

    _ = try await sut.from(bucketID).list()

    #expect(capturedRequests[1].value(forHTTPHeaderField: "X-Child-Header") == nil)
  }

  @Test
  func settingHeader_onTopLevelClientPropagatesToFileApi() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sut = try makeSUT(fetch: { request in
      capturedRequest.setValue(request)
      return (
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
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ =
      try await sut
      .settingHeader(name: .init("X-Client-Header")!, value: "client-value")
      .from(bucketID)
      .list()

    #expect(
      capturedRequest.value?.value(forHTTPHeaderField: "X-Client-Header") == "client-value")
  }
}
