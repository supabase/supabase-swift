import ConcurrencyExtras
import Foundation
import InlineSnapshotTesting
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class SupabaseStorageTests: XCTestCase {
  static let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketId = "tests"

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StorageURLProtocolMock.self]
    return URLSession(configuration: configuration)
  }()

  override func tearDown() {
    super.tearDown()
    StorageURLProtocolMock.requestHandler.setValue(nil)
  }

  func testGetPublicURL() throws {
    let sut = makeSUT()

    let path = "README.md"

    let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)")

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

  func testCreateSignedURLs() async throws {
    StorageURLProtocolMock.requestHandler.setValue { _ in
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
          url: Self.supabaseURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }

    let sut = makeSUT()
    let results: [SignedURLResult] = try await sut.from(bucketId).createSignedURLs(
      paths: ["file1.txt", "file2.txt"],
      expiresIn: 60
    )

    XCTAssertEqual(results.count, 2)
    guard case .success(let path0, let url0) = results[0] else {
      return XCTFail("Expected success for file1.txt")
    }
    XCTAssertEqual(path0, "file1.txt")
    XCTAssertEqual(
      url0.absoluteString,
      "http://localhost:54321/storage/v1/sign/file1.txt?token=abc.def.ghi")
    guard case .success(let path1, let url1) = results[1] else {
      return XCTFail("Expected success for file2.txt")
    }
    XCTAssertEqual(path1, "file2.txt")
    XCTAssertEqual(
      url1.absoluteString,
      "http://localhost:54321/storage/v1/sign/file2.txt?token=abc.def.ghi")
  }

  #if !os(Linux) && !os(Android)
    func testUploadData() async throws {
      testingBoundary.setValue("alamofire.boundary.c21f947c1c7b0c57")

      StorageURLProtocolMock.requestHandler.setValue { request in
        assertInlineSnapshot(of: request, as: .curl) {
          #"""
          curl \
          	--request POST \
          	--header "Accept: application/json" \
          	--header "Apikey: test.api.key" \
          	--header "Cache-Control: max-age=14400" \
          	--header "Content-Length: 390" \
          	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.c21f947c1c7b0c57" \
          	--header "X-Client-Info: storage-swift/x.y.z" \
          	--header "x-upsert: false" \
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
            url: Self.supabaseURL,
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

      StorageURLProtocolMock.requestHandler.setValue { request in
        assertInlineSnapshot(of: request, as: .curl) {
          #"""
          curl \
          	--request POST \
          	--header "Accept: application/json" \
          	--header "Apikey: test.api.key" \
          	--header "Cache-Control: max-age=3600" \
          	--header "Content-Length: 29907" \
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
            url: Self.supabaseURL,
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

  private func makeSUT() -> StorageClient {
    StorageClient.test(
      supabaseURL: Self.supabaseURL.absoluteString,
      apiKey: "test.api.key",
      session: session
    )
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent(fileName)
  }

}

private final class StorageURLProtocolMock: URLProtocol {
  static let requestHandler = LockIsolated<(@Sendable (URLRequest) throws -> (Data, URLResponse))?>(
    nil
  )

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    do {
      guard let handler = Self.requestHandler.value else {
        throw URLError(.badServerResponse)
      }

      let (data, response) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
