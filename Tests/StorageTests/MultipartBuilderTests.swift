import Foundation
import Testing

@testable import Storage

@Suite
struct MultipartBuilderTests {
  @Test func buildInMemory_emptyParts() throws {
    let body = try MultipartBuilder(boundary: "empty-boundary").buildInMemory()
    #expect(body == Data())
  }

  @Test func buildInMemory_exactTextAndDataParts() throws {
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
    #expect(body == expected)
  }

  @Test func buildToTempFile_emptyParts() throws {
    let outputURL = try MultipartBuilder(boundary: "empty-boundary").buildToTempFile()
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let outputData = try Data(contentsOf: outputURL)
    #expect(outputData == Data())
  }

  @Test func buildToTempFile_exactFilePartWithExplicitFileName() throws {
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
    let outputData = try Data(contentsOf: outputURL)
    #expect(outputData == expected)
  }

  @Test func addFile_defaultsFileNameToLastPathComponent() throws {
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
    #expect(body == expected)
  }

  @Test func contentTypeIncludesBoundary() {
    let builder = MultipartBuilder(boundary: "content-type-boundary")
    #expect(builder.contentType == "multipart/form-data; boundary=content-type-boundary")
  }
}
