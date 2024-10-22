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

  override func invokeTest() {
    withSnapshotTesting(record: .missing) {
      super.invokeTest()
    }
  }

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

  func testUploadData() async {
    testingBoundary = "alamofire.boundary.c21f947c1c7b0c57"

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
      throw UnimplementedFailure(description: "unimplemented")
    }

    let sut = makeSUT()

    _ = try? await sut.from(bucketId)
      .upload(
        "file1.txt",
        data: "test data".data(using: .utf8)!,
        options: FileOptions(
          cacheControl: "14400",
          metadata: ["key": "value"]
        )
      )
  }

  func testUploadFileURL() async {
    testingBoundary = "alamofire.boundary.c21f947c1c7b0c57"

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
      throw UnimplementedFailure(description: "unimplemented")
    }

    let sut = makeSUT()

    _ = try? await sut.from(bucketId)
      .upload(
        "sadcat.jpg",
        fileURL: uploadFileURL("sadcat.jpg"),
        options: FileOptions(
          metadata: ["key": "value"]
        )
      )
  }

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
}
