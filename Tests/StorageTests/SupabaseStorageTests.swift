import Foundation
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class SupabaseStorageTests: XCTestCase {
  let supabaseURL = "http://localhost:54321/storage/v1"
  let bucketId = "tests"

  lazy var storage = SupabaseStorageClient.test(
    supabaseURL: supabaseURL,
    apiKey: "test.api.key"
  )

  func testGetPublicURL() async throws {
    let path = "README.md"

    let baseUrl = try storage.from(bucketId).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(supabaseURL)/object/public/\(bucketId)/\(path)")

    let baseUrlWithDownload = try storage.from(bucketId).getPublicURL(
      path: path,
      download: true
    )
    XCTAssertEqual(
      baseUrlWithDownload.absoluteString,
      "\(supabaseURL)/object/public/\(bucketId)/\(path)?download="
    )

    let baseUrlWithDownloadAndFileName = try storage.from(bucketId).getPublicURL(
      path: path, download: "test"
    )
    XCTAssertEqual(
      baseUrlWithDownloadAndFileName.absoluteString,
      "\(supabaseURL)/object/public/\(bucketId)/\(path)?download=test"
    )

    let baseUrlWithAllOptions = try storage.from(bucketId).getPublicURL(
      path: path, download: "test",
      options: TransformOptions(width: 300, height: 300)
    )
    XCTAssertEqual(
      baseUrlWithAllOptions.absoluteString,
      "\(supabaseURL)/render/image/public/\(bucketId)/\(path)?download=test&width=300&height=300&resize=cover&quality=80&format=origin"
    )
  }
}
