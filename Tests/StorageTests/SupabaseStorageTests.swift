import Foundation
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class SupabaseStorageTests: XCTestCase {
  static var apiKey: String {
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  }

  static var supabaseURL: String {
    "http://localhost:54321/storage/v1"
  }

  let bucket = "public"

  let storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: supabaseURL)!,
      headers: [
        "Authorization": "Bearer \(apiKey)",
        "apikey": apiKey,
      ]
    )
  )

  let uploadData = try? Data(
    contentsOf: URL(
      string: "https://raw.githubusercontent.com/supabase-community/storage-swift/main/README.md"
    )!
  )

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )

    _ = try? await storage.emptyBucket(id: bucket)
    _ = try? await storage.deleteBucket(id: bucket)

    _ = try await storage.createBucket(id: bucket, options: BucketOptions(public: true))
  }

  func testListBuckets() async throws {
    let buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets.map(\.name), [bucket])
  }

  func testFileIntegration() async throws {
    try await uploadTestData()

    let files = try await storage.from(id: bucket).list()
    XCTAssertEqual(files.map(\.name), ["README.md"])

    let downloadedData = try await storage.from(id: bucket).download(path: "README.md")
    XCTAssertEqual(downloadedData, uploadData)

    let removedFiles = try await storage.from(id: bucket).remove(paths: ["README.md"])
    XCTAssertEqual(removedFiles.map(\.name), ["README.md"])
  }

  func testGetPublicURL() async throws {
    try await uploadTestData()

    let path = "README.md"

    let baseUrl = try storage.from(id: bucket).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(Self.supabaseURL)/object/public/\(bucket)/\(path)")

    let baseUrlWithDownload = try storage.from(id: bucket).getPublicURL(path: path, download: true)
    XCTAssertEqual(
      baseUrlWithDownload.absoluteString,
      "\(Self.supabaseURL)/object/public/\(bucket)/\(path)?download="
    )

    let baseUrlWithDownloadAndFileName = try storage.from(id: bucket).getPublicURL(
      path: path, download: true, fileName: "test"
    )
    XCTAssertEqual(
      baseUrlWithDownloadAndFileName.absoluteString,
      "\(Self.supabaseURL)/object/public/\(bucket)/\(path)?download=test"
    )

    let baseUrlWithAllOptions = try storage.from(id: bucket).getPublicURL(
      path: path, download: true, fileName: "test",
      options: TransformOptions(width: 300, height: 300)
    )
    XCTAssertEqual(
      baseUrlWithAllOptions.absoluteString,
      "\(Self.supabaseURL)/render/image/public/\(bucket)/\(path)?download=test&width=300&height=300&resize=cover&quality=80&format=origin"
    )
  }

  private func uploadTestData() async throws {
    let file = File(
      name: "README.md", data: uploadData ?? Data(), fileName: "README.md", contentType: "text/html"
    )
    _ = try await storage.from(id: bucket).upload(
      path: "README.md", file: file, fileOptions: FileOptions(cacheControl: "3600")
    )
  }
}
