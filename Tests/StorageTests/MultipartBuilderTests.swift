import XCTest

@testable import Storage

final class MultipartBuilderTests: XCTestCase {
  func testBuildInMemoryReturnsEmptyDataWhenThereAreNoParts() throws {
    let body = try MultipartBuilder(boundary: "empty-boundary").buildInMemory()

    XCTAssertEqual(body, Data())
  }

  func testBuildInMemoryIncludesExactTextAndDataParts() throws {
    let boundary = "test-boundary"
    let payload = Data("hello world".utf8)

    let body = try MultipartBuilder(boundary: boundary)
      .addText(name: "cacheControl", value: "3600")
      .addData(
        name: "file",
        data: payload,
        fileName: "hello.txt",
        mimeType: "text/plain"
      )
      .buildInMemory()

    let expectedString =
      "--test-boundary\r\n"
      + "Content-Disposition: form-data; name=\"cacheControl\"\r\n"
      + "\r\n"
      + "3600\r\n"
      + "--test-boundary\r\n"
      + "Content-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\n"
      + "Content-Type: text/plain\r\n"
      + "\r\n"
      + "hello world\r\n"
      + "--test-boundary--\r\n"
    let expected = Data(expectedString.utf8)
    XCTAssertEqual(body, expected)
  }

  func testBuildToTempFileReturnsEmptyFileWhenThereAreNoParts() throws {
    let outputURL = try MultipartBuilder(boundary: "empty-boundary").buildToTempFile()
    defer { try? FileManager.default.removeItem(at: outputURL) }

    XCTAssertEqual(try Data(contentsOf: outputURL), Data())
  }

  func testBuildToTempFileIncludesExactFilePartWithExplicitFileName() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let sourceURL = tempDirectory.appendingPathComponent("source-\(UUID().uuidString).txt")
    try Data("file body".utf8).write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let outputURL = try MultipartBuilder(boundary: "file-boundary")
      .addFile(
        name: "upload",
        fileURL: sourceURL,
        fileName: "explicit.txt",
        mimeType: "text/plain"
      )
      .buildToTempFile()
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let expectedString =
      "--file-boundary\r\n"
      + "Content-Disposition: form-data; name=\"upload\"; filename=\"explicit.txt\"\r\n"
      + "Content-Type: text/plain\r\n"
      + "\r\n"
      + "file body\r\n"
      + "--file-boundary--\r\n"
    let expected = Data(expectedString.utf8)
    XCTAssertEqual(try Data(contentsOf: outputURL), expected)
  }

  func testAddFileDefaultsFileNameToLastPathComponent() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let sourceURL = tempDirectory.appendingPathComponent("default-name.txt")
    try Data("file body".utf8).write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let body = try MultipartBuilder(boundary: "default-filename-boundary")
      .addFile(
        name: "upload",
        fileURL: sourceURL,
        mimeType: "text/plain"
      )
      .buildInMemory()

    let expectedString =
      "--default-filename-boundary\r\n"
      + "Content-Disposition: form-data; name=\"upload\"; filename=\"default-name.txt\"\r\n"
      + "Content-Type: text/plain\r\n"
      + "\r\n"
      + "file body\r\n"
      + "--default-filename-boundary--\r\n"
    let expected = Data(expectedString.utf8)
    XCTAssertEqual(body, expected)
  }

  func testContentTypeIncludesBoundary() {
    let builder = MultipartBuilder(boundary: "content-type-boundary")

    XCTAssertEqual(
      builder.contentType,
      "multipart/form-data; boundary=content-type-boundary"
    )
  }
}
