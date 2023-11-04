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

  let bucketId = "tests"

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

    try? await storage.emptyBucket(bucketId)
    try? await storage.deleteBucket(bucketId)

    try await storage.createBucket(bucketId, options: BucketOptions(public: true))
  }

  func testUpdateBucket() async throws {
    var bucket = try await storage.getBucket(bucketId)
    XCTAssertTrue(bucket.isPublic)

    try await storage.updateBucket(bucketId, options: BucketOptions(public: false))
    bucket = try await storage.getBucket(bucketId)
    XCTAssertFalse(bucket.isPublic)
  }

  func testListBuckets() async throws {
    let buckets = try await storage.listBuckets()
    XCTAssertTrue(buckets.contains { $0.id == bucketId })
  }

  func testFileIntegration() async throws {
    var files = try await storage.from(bucketId).list()
    XCTAssertTrue(files.isEmpty)

    try await uploadTestData()

    files = try await storage.from(bucketId).list()
    XCTAssertEqual(files.map(\.name), ["README.md"])

    let downloadedData = try await storage.from(bucketId).download(path: "README.md")
    XCTAssertEqual(downloadedData, uploadData)

    try await storage.from(bucketId).move(from: "README.md", to: "README_2.md")

    var searchedFiles = try await storage.from(bucketId)
      .list(options: .init(search: "README.md"))
    XCTAssertTrue(searchedFiles.isEmpty)

    try await storage.from(bucketId).copy(from: "README_2.md", to: "README.md")
    searchedFiles = try await storage.from(bucketId).list(options: .init(search: "README.md"))
    XCTAssertEqual(searchedFiles.map(\.name), ["README.md"])

    let removedFiles = try await storage.from(bucketId).remove(paths: ["README_2.md"])
    XCTAssertEqual(removedFiles.map(\.name), ["README_2.md"])
  }

  func testGetPublicURL() async throws {
    try await uploadTestData()

    let path = "README.md"

    let baseUrl = try storage.from(bucketId).getPublicURL(path: path)
    XCTAssertEqual(baseUrl.absoluteString, "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)")

    let baseUrlWithDownload = try storage.from(bucketId).getPublicURL(
      path: path,
      download: true
    )
    XCTAssertEqual(
      baseUrlWithDownload.absoluteString,
      "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)?download="
    )

    let baseUrlWithDownloadAndFileName = try storage.from(bucketId).getPublicURL(
      path: path, download: "test"
    )
    XCTAssertEqual(
      baseUrlWithDownloadAndFileName.absoluteString,
      "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)?download=test"
    )

    let baseUrlWithAllOptions = try storage.from(bucketId).getPublicURL(
      path: path, download: "test",
      options: TransformOptions(width: 300, height: 300)
    )
    XCTAssertEqual(
      baseUrlWithAllOptions.absoluteString,
      "\(Self.supabaseURL)/render/image/public/\(bucketId)/\(path)?download=test&width=300&height=300&resize=cover&quality=80&format=origin"
    )
  }

  func testCreateSignedURL() async throws {
    try await uploadTestData()

    let path = "README.md"

    let url = try await storage.from(bucketId).createSignedURL(
      path: path,
      expiresIn: 60,
      download: "README_local.md"
    )
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: true))

    let downloadQuery = components.queryItems?.first(where: { $0.name == "download" })
    XCTAssertEqual(downloadQuery?.value, "README_local.md")
    XCTAssertEqual(components.path, "/storage/v1/object/sign/\(bucketId)/\(path)")
  }

  func testUpdate() async throws {
    try await uploadTestData()

    let dataToUpdate = try? Data(
      contentsOf: URL(
        string: "https://raw.githubusercontent.com/supabase-community/supabase-swift/master/README.md"
      )!
    )

    try await storage.from(bucketId).update(
      path: "README.md",
      file: File(name: "README.md", data: dataToUpdate ?? Data(), fileName: nil, contentType: nil)
    )
  }

  private func uploadTestData() async throws {
    let file = File(
      name: "README.md", data: uploadData ?? Data(), fileName: "README.md", contentType: "text/html"
    )
    _ = try await storage.from(bucketId).upload(
      path: "README.md", file: file, fileOptions: FileOptions(cacheControl: "3600")
    )
  }
}
