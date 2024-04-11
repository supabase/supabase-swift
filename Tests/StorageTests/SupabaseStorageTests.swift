import CustomDump
import Foundation
@testable import Storage
import XCTest
import XCTestDynamicOverlay

final class SupabaseStorageTests: XCTestCase {
  let supabaseURL = URL(string: "http://localhost:54321/storage/v1")!
  let bucketId = "tests"

  var sessionMock = StorageHTTPSession(
    fetch: unimplemented("StorageHTTPSession.fetch"),
    upload: unimplemented("StorageHTTPSession.upload")
  )

  func testGetPublicURL() async throws {
    let sut = makeSUT()

    let path = "README.md"

    let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(supabaseURL)/object/public/\(bucketId)/\(path)")

    let baseUrlWithDownload = try sut.from(bucketId).getPublicURL(
      path: path,
      download: true
    )
    XCTAssertEqual(
      baseUrlWithDownload.absoluteString,
      "\(supabaseURL)/object/public/\(bucketId)/\(path)?download="
    )

    let baseUrlWithDownloadAndFileName = try sut.from(bucketId).getPublicURL(
      path: path, download: "test"
    )
    XCTAssertEqual(
      baseUrlWithDownloadAndFileName.absoluteString,
      "\(supabaseURL)/object/public/\(bucketId)/\(path)?download=test"
    )

    let baseUrlWithAllOptions = try sut.from(bucketId).getPublicURL(
      path: path, download: "test",
      options: TransformOptions(width: 300, height: 300)
    )
    XCTAssertEqual(
      baseUrlWithAllOptions.absoluteString,
      "\(supabaseURL)/render/image/public/\(bucketId)/\(path)?download=test&width=300&height=300&resize=cover&quality=80&format=origin"
    )
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

    XCTAssertNoDifference(
      urls.map(\.absoluteString),
      [
        "\(supabaseURL.absoluteString)/sign/file1.txt?token=abc.def.ghi",
        "\(supabaseURL.absoluteString)/sign/file2.txt?token=abc.def.ghi",
      ]
    )
  }

  private func makeSUT() -> SupabaseStorageClient {
    SupabaseStorageClient.test(
      supabaseURL: supabaseURL.absoluteString,
      apiKey: "test.api.key",
      session: sessionMock
    )
  }
}
