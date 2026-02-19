import CustomDump
import Foundation
import InlineSnapshotTesting
import XCTest
import XCTestDynamicOverlay

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class SupabaseStorageTests: XCTestCase {
  let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketId = "tests"

  var sessionMock = StorageHTTPSession(
    fetch: unimplemented("StorageHTTPSession.fetch"),
    upload: unimplemented("StorageHTTPSession.upload")
  )

  func testGetPublicURL() throws {
    let sut = makeSUT()

    let path = "README.md"

    let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(supabaseURL)/object/public/\(bucketId)/\(path)")

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
      http://localhost:54321/storage/v1/render/image/public/tests/README.md?download=test&width=300&height=300&quality=80
      """
    }
  }

  func testCreateSignedURLs() async throws {
    sessionMock.fetch = { _ in
      (
        """
        [
          {
            "signedURL": "/sign/file1.txt?token=abc.def.ghi"
          },
          {
            "signedURL": "/sign/file2.txt?token=abc.def.ghi"
          },
        ]
        """.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }

    let sut = makeSUT()
    let urls = try await sut.from(bucketId).createSignedURLs(
      paths: ["file1.txt", "file2.txt"],
      expiresIn: 60
    )

    assertInlineSnapshot(of: urls, as: .description) {
      """
      [http://localhost:54321/storage/v1/sign/file1.txt?token=abc.def.ghi, http://localhost:54321/storage/v1/sign/file2.txt?token=abc.def.ghi]
      """
    }
  }

  #if !os(Linux) && !os(Android)
    func testUploadData() async throws {
      testingBoundary.setValue("alamofire.boundary.c21f947c1c7b0c57")

      sessionMock.fetch = { request in
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
      }

      let sut = makeSUT()

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

    func testUploadFileURL() async throws {
      testingBoundary.setValue("alamofire.boundary.c21f947c1c7b0c57")

      sessionMock.fetch = { request in
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
      }

      let sut = makeSUT()

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

  private func makeSUT() -> SupabaseStorageClient {
    SupabaseStorageClient.test(
      supabaseURL: supabaseURL.absoluteString,
      apiKey: "test.api.key",
      session: sessionMock
    )
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #file)
      .deletingLastPathComponent()
      .appendingPathComponent(fileName)
  }

  // MARK: - setHeader Tests

  func testSetHeader_setsHeaderOnRequest() async throws {
    var capturedRequest: URLRequest?
    sessionMock.fetch = { request in
      capturedRequest = request
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
    }

    let sut = makeSUT()

    _ = try await sut.from(bucketId)
      .setHeader(name: "X-Custom-Header", value: "custom-value")
      .list()

    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Custom-Header"), "custom-value")
  }

  func testSetHeader_supportsMethodChaining() async throws {
    var capturedRequest: URLRequest?
    sessionMock.fetch = { request in
      capturedRequest = request
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
    }

    let sut = makeSUT()

    _ = try await sut.from(bucketId)
      .setHeader(name: "X-Header-A", value: "value-a")
      .setHeader(name: "X-Header-B", value: "value-b")
      .list()

    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Header-A"), "value-a")
    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Header-B"), "value-b")
  }

  func testSetHeader_overridesExistingHeader() async throws {
    var capturedRequest: URLRequest?
    sessionMock.fetch = { request in
      capturedRequest = request
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
    }

    let sut = makeSUT()

    _ = try await sut.from(bucketId)
      .setHeader(name: "X-Custom-Header", value: "initial-value")
      .setHeader(name: "X-Custom-Header", value: "updated-value")
      .list()

    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Custom-Header"), "updated-value")
  }

  func testSetHeader_doesNotMutateParentClientHeaders() async throws {
    var capturedRequestFromFileApi: URLRequest?
    var capturedRequestFromNewFileApi: URLRequest?

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

    // Setup mock to capture requests
    sessionMock.fetch = { [self] request in
      // Track which request this is based on the header
      if request.value(forHTTPHeaderField: "X-Child-Header") != nil {
        capturedRequestFromFileApi = request
      } else {
        capturedRequestFromNewFileApi = request
      }
      return (
        listResponse.data(using: .utf8)!,
        HTTPURLResponse(
          url: self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }

    let sut = makeSUT()

    // First, make a request with setHeader on StorageFileApi
    _ = try await sut.from(bucketId)
      .setHeader(name: "X-Child-Header", value: "child-value")
      .list()

    XCTAssertEqual(
      capturedRequestFromFileApi?.value(forHTTPHeaderField: "X-Child-Header"),
      "child-value"
    )

    // Then make a request from a new StorageFileApi instance (via sut.from())
    // The new instance should NOT have the previous instance's header
    _ = try await sut.from(bucketId).list()

    // The new StorageFileApi instance should NOT have the previous instance's header
    XCTAssertNil(capturedRequestFromNewFileApi?.value(forHTTPHeaderField: "X-Child-Header"))
  }
}
