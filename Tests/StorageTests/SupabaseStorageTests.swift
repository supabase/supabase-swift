import ConcurrencyExtras
import Foundation
import InlineSnapshotTesting
import Testing
import XCTestDynamicOverlay

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct SupabaseStorageTests {
  let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketId = "tests"

  @Test
  func getPublicURL() throws {
    let sut = makeSUT()

    let path = "README.md"

    let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
    #expect(baseUrl.absoluteString == "\(supabaseURL)/object/public/\(bucketId)/\(path)")

    let baseUrlWithDownload = try sut.from(bucketId).getPublicURL(
      path: path,
      download: true
    )
    assertInlineSnapshot(of: baseUrlWithDownload, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=
      """
    }

    let baseUrlWithDownloadAndFileName = try sut.from(bucketId).getPublicURL(
      path: path, download: "test"
    )
    assertInlineSnapshot(of: baseUrlWithDownloadAndFileName, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=test
      """
    }

    let baseUrlWithAllOptions = try sut.from(bucketId).getPublicURL(
      path: path, download: "test",
      options: TransformOptions(width: 300, height: 300)
    )
    assertInlineSnapshot(of: baseUrlWithAllOptions, as: .description) {
      """
      http://localhost:54321/storage/v1/render/image/public/tests/README.md?download=test&width=300&height=300
      """
    }
  }

  @Test
  func createSignedURLs() async throws {
    let sessionMock = StorageHTTPSession(
      fetch: { _ in
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
      },
      upload: unimplemented("StorageHTTPSession.upload")
    )

    let sut = makeSUT(session: sessionMock)
    let results: [SignedURLResult] = try await sut.from(bucketId).createSignedURLs(
      paths: ["file1.txt", "file2.txt"],
      expiresIn: 60
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

  #if !os(Linux) && !os(Android)
    @Test
    func uploadData() async throws {
      testingBoundary.setValue("alamofire.boundary.c21f947c1c7b0c57")

      let sessionMock = StorageHTTPSession(
        fetch: { request in
          assertInlineSnapshot(of: request, as: .curl) {
            #"""
            curl \
            	--request POST \
            	--header "Apikey: test.api.key" \
            	--header "Authorization: Bearer test.api.key" \
            	--header "Cache-Control: max-age=14400" \
            	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.c21f947c1c7b0c57" \
            	--header "X-Client-Info: storage-swift/x.y.z" \
            	--header "x-upsert: false" \
            	--data "--alamofire.boundary.c21f947c1c7b0c57\#r
            Content-Disposition: form-data; name=\"cacheControl\"\#r
            \#r
            14400\#r
            --alamofire.boundary.c21f947c1c7b0c57\#r
            Content-Disposition: form-data; name=\"metadata\"\#r
            \#r
            {\"key\":\"value\"}\#r
            --alamofire.boundary.c21f947c1c7b0c57\#r
            Content-Disposition: form-data; name=\"\"; filename=\"file1.txt\"\#r
            Content-Type: text/plain\#r
            \#r
            test data\#r
            --alamofire.boundary.c21f947c1c7b0c57--\#r
            " \
            	"http://localhost:54321/storage/v1/object/tests/file1.txt"
            """#
          }
          return (
            """
            {
              "Id": "tests/file1.txt",
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
        },
        upload: unimplemented("StorageHTTPSession.upload")
      )

      let sut = makeSUT(session: sessionMock)

      try await sut.from(bucketId)
        .upload(
          "file1.txt",
          data: "test data".data(using: .utf8)!,
          options: FileOptions(
            cacheControl: "14400",
            metadata: ["key": "value"]
          )
        )
    }

    @Test
    func uploadFileURL() async throws {
      testingBoundary.setValue("alamofire.boundary.c21f947c1c7b0c57")

      let sessionMock = StorageHTTPSession(
        fetch: { request in
          assertInlineSnapshot(of: request, as: .curl) {
            #"""
            curl \
            	--request POST \
            	--header "Apikey: test.api.key" \
            	--header "Authorization: Bearer test.api.key" \
            	--header "Cache-Control: max-age=3600" \
            	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.c21f947c1c7b0c57" \
            	--header "X-Client-Info: storage-swift/x.y.z" \
            	--header "x-upsert: false" \
            	"http://localhost:54321/storage/v1/object/tests/sadcat.jpg"
            """#
          }
          return (
            """
            {
              "Id": "tests/file1.txt",
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
        },
        upload: unimplemented("StorageHTTPSession.upload")
      )

      let sut = makeSUT(session: sessionMock)

      try await sut.from(bucketId)
        .upload(
          "sadcat.jpg",
          fileURL: uploadFileURL("sadcat.jpg"),
          options: FileOptions(
            metadata: ["key": "value"]
          )
        )
    }
  #endif

  private func makeSUT(
    session: StorageHTTPSession = StorageHTTPSession(
      fetch: unimplemented("StorageHTTPSession.fetch"),
      upload: unimplemented("StorageHTTPSession.upload")
    )
  ) -> SupabaseStorageClient {
    SupabaseStorageClient.test(
      supabaseURL: supabaseURL.absoluteString,
      apiKey: "test.api.key",
      session: session
    )
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent(fileName)
  }

  // MARK: - setValue(_:forHTTPHeaderField:) Tests

  @Test
  func setHeader_setsHeaderOnRequest() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sessionMock = StorageHTTPSession(
      fetch: { request in
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
      },
      upload: unimplemented("StorageHTTPSession.upload")
    )

    let sut = makeSUT(session: sessionMock)

    _ = try await sut.from(bucketId)
      .setHeader("custom-value", forKey: "X-Custom-Header")
      .list()

    #expect(
      capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header") == "custom-value")
  }

  @Test
  func setHeader_supportsMethodChaining() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sessionMock = StorageHTTPSession(
      fetch: { request in
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
      },
      upload: unimplemented("StorageHTTPSession.upload")
    )

    let sut = makeSUT(session: sessionMock)

    _ = try await sut.from(bucketId)
      .setHeader("value-a", forKey: "X-Header-A")
      .setHeader("value-b", forKey: "X-Header-B")
      .list()

    #expect(capturedRequest.value?.value(forHTTPHeaderField: "X-Header-A") == "value-a")
    #expect(capturedRequest.value?.value(forHTTPHeaderField: "X-Header-B") == "value-b")
  }

  @Test
  func setHeader_overridesExistingHeader() async throws {
    let capturedRequest = LockIsolated(URLRequest?.none)
    let sessionMock = StorageHTTPSession(
      fetch: { request in
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
      },
      upload: unimplemented("StorageHTTPSession.upload")
    )

    let sut = makeSUT(session: sessionMock)

    _ = try await sut.from(bucketId)
      .setHeader("initial-value", forKey: "X-Custom-Header")
      .setHeader("updated-value", forKey: "X-Custom-Header")
      .list()

    #expect(
      capturedRequest.value?.value(forHTTPHeaderField: "X-Custom-Header") == "updated-value")
  }

  @Test
  func setHeader_doesNotMutateParentClientHeaders() async throws {
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

    let sessionMock = StorageHTTPSession(
      fetch: { request in
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
      },
      upload: unimplemented("StorageHTTPSession.upload")
    )

    let sut = makeSUT(session: sessionMock)

    // First, make a request with setHeader on StorageFileApi
    _ = try await sut.from(bucketId)
      .setHeader("child-value", forKey: "X-Child-Header")
      .list()

    #expect(
      capturedRequests[0].value(forHTTPHeaderField: "X-Child-Header")
        == "child-value"
    )

    // Then make a request from a new StorageFileApi instance (via sut.from())
    // The new instance should NOT have the previous instance's header
    _ = try await sut.from(bucketId).list()

    // The new StorageFileApi instance should NOT have the previous instance's header
    #expect(capturedRequests[1].value(forHTTPHeaderField: "X-Child-Header") == nil)
  }
}
