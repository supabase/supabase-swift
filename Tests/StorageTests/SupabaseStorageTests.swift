import ConcurrencyExtras
import Foundation
import InlineSnapshotTesting
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct SupabaseStorageTests {
  static let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketId = "tests"
  let session: URLSession

  init() {
    StorageURLProtocolMock.requestHandler.setValue(nil)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StorageURLProtocolMock.self]
    session = URLSession(configuration: configuration)
  }

  @Test func getPublicURL() throws {
    let sut = makeSUT()
    let path = "README.md"

    let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
    #expect(
      baseUrl.absoluteString == "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)"
    )

    let baseUrlWithDownload = try sut.from(bucketId).getPublicURL(
      path: path,
      download: .withOriginalName
    )
    assertInlineSnapshot(of: baseUrlWithDownload, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=
      """
    }

    let baseUrlWithDownloadAndFileName = try sut.from(bucketId).getPublicURL(
      path: path, download: .named("test")
    )
    assertInlineSnapshot(of: baseUrlWithDownloadAndFileName, as: .description) {
      """
      http://localhost:54321/storage/v1/object/public/tests/README.md?download=test
      """
    }

    let baseUrlWithAllOptions = try sut.from(bucketId).getPublicURL(
      path: path, download: .named("test"),
      options: TransformOptions(width: 300, height: 300)
    )
    assertInlineSnapshot(of: baseUrlWithAllOptions, as: .description) {
      """
      http://localhost:54321/storage/v1/render/image/public/tests/README.md?download=test&width=300&height=300
      """
    }
  }

  @Test func createSignedURLs() async throws {
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
        == "http://localhost:54321/storage/v1/sign/file1.txt?token=abc.def.ghi"
    )
    guard case .success(let path1, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(path1 == "file2.txt")
    #expect(
      url1.absoluteString
        == "http://localhost:54321/storage/v1/sign/file2.txt?token=abc.def.ghi"
    )
  }

  #if !os(Linux) && !os(Android)
    @Test func uploadData() async throws {
      let capturedRequest = LockIsolated<URLRequest?>(nil)

      StorageURLProtocolMock.requestHandler.setValue { request in
        capturedRequest.setValue(request)
        let data = Data(
          """
          {"Key":"tests/file1.txt","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}
          """.utf8
        )
        return (
          data,
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
        .uploadMultipart(
          "file1.txt",
          data: "test data".data(using: .utf8)!,
          options: FileOptions(
            cacheControl: "14400",
            metadata: ["key": "value"]
          )
        ).value

      let req = try #require(capturedRequest.value)
      #expect(req.httpMethod == "POST")
    }

    @Test func uploadFileURL() async throws {
      let capturedRequest = LockIsolated<URLRequest?>(nil)

      StorageURLProtocolMock.requestHandler.setValue { request in
        capturedRequest.setValue(request)
        let data = Data(
          """
          {"Key":"tests/sadcat.jpg","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}
          """.utf8
        )
        return (
          data,
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
        .uploadMultipart(
          "sadcat.jpg",
          fileURL: uploadFileURL("sadcat.jpg"),
          options: FileOptions(
            metadata: ["key": "value"]
          )
        ).value

      let req = try #require(capturedRequest.value)
      #expect(req.httpMethod == "POST")
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
