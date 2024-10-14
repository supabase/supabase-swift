import CustomDump
import Foundation
import InlineSnapshotTesting
@testable import Storage
import XCTest
import XCTestDynamicOverlay

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

  private func makeSUT() -> SupabaseStorageClient {
    SupabaseStorageClient.test(
      supabaseURL: supabaseURL.absoluteString,
      apiKey: "test.api.key",
      session: sessionMock
    )
  }
}
