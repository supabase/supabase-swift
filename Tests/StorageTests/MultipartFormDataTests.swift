import XCTest

@testable import Storage

final class MultipartFormDataTests: XCTestCase {
  func testBoundaryGeneration() {
    let formData = MultipartFormData()
    XCTAssertFalse(formData.boundary.isEmpty)
    XCTAssertTrue(formData.contentType.contains("multipart/form-data; boundary="))
  }

  func testAppendingData() {
    let formData = MultipartFormData()
    let testData = "Hello World".data(using: .utf8)!

    formData.append(testData, withName: "test", fileName: "test.txt", mimeType: "text/plain")

    XCTAssertGreaterThan(formData.contentLength, 0)
  }

  func testContentHeaders() {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(
      testData,
      withName: "file",
      fileName: "test.txt",
      mimeType: "text/plain"
    )

    XCTAssertTrue(formData.contentType.hasPrefix("multipart/form-data"))
  }

  func testCustomBoundary() {
    let customBoundary = "test-boundary-12345"
    let formData = MultipartFormData(boundary: customBoundary)

    XCTAssertEqual(formData.boundary, customBoundary)
    XCTAssertTrue(formData.contentType.contains(customBoundary))
  }

  func testAppendDataWithoutFileName() {
    let formData = MultipartFormData()
    let testData = "Test data".data(using: .utf8)!

    formData.append(testData, withName: "field")

    XCTAssertGreaterThan(formData.contentLength, 0)
  }

  func testMultipleAppends() {
    let formData = MultipartFormData()
    let data1 = "First".data(using: .utf8)!
    let data2 = "Second".data(using: .utf8)!

    formData.append(data1, withName: "field1", fileName: "file1.txt", mimeType: "text/plain")
    formData.append(data2, withName: "field2", fileName: "file2.txt", mimeType: "text/plain")

    XCTAssertGreaterThan(formData.contentLength, UInt64(data1.count + data2.count))
  }

  func testEncodeFormData() throws {
    let formData = MultipartFormData()
    let testData = "Test content".data(using: .utf8)!

    formData.append(testData, withName: "file", fileName: "test.txt", mimeType: "text/plain")

    let encoded = try formData.encode()
    XCTAssertGreaterThan(encoded.count, 0)

    // Verify encoded data contains boundary
    let encodedString = String(data: encoded, encoding: .utf8)
    XCTAssertNotNil(encodedString)
    XCTAssertTrue(encodedString!.contains(formData.boundary))
  }

  func testAppendFileURL() throws {
    let formData = MultipartFormData()

    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).txt")
    let testContent = "File content".data(using: .utf8)!

    try testContent.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    formData.append(fileURL, withName: "upload")

    XCTAssertGreaterThan(formData.contentLength, 0)
  }

  func testAppendFileURLWithCustomMetadata() throws {
    let formData = MultipartFormData()

    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("custom-\(UUID().uuidString).json")
    let testContent = #"{"key": "value"}"#.data(using: .utf8)!

    try testContent.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    formData.append(fileURL, withName: "data", fileName: "custom.json", mimeType: "application/json")

    XCTAssertGreaterThan(formData.contentLength, 0)
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
  func testAppendInvalidFileURL() {
    let formData = MultipartFormData()
    let invalidURL = URL(fileURLWithPath: "/nonexistent/path/file.txt")

    formData.append(invalidURL, withName: "file")

    // Should fail during encoding
    XCTAssertThrowsError(try formData.encode())
  }

  func testAppendNonFileURL() {
    let formData = MultipartFormData()
    let httpURL = URL(string: "https://example.com/file.txt")!

    formData.append(httpURL, withName: "file", fileName: "file.txt", mimeType: "text/plain")

    // Should fail during encoding
    XCTAssertThrowsError(try formData.encode())
  }

  func testAppendDirectory() throws {
    let formData = MultipartFormData()

    // Use a known directory
    let dirURL = FileManager.default.temporaryDirectory

    formData.append(dirURL, withName: "dir")

    // Should fail during encoding
    XCTAssertThrowsError(try formData.encode())
  }
  #endif

  func testAppendInputStream() {
    let formData = MultipartFormData()
    let testData = "Stream data".data(using: .utf8)!
    let stream = InputStream(data: testData)

    formData.append(
      stream,
      withLength: UInt64(testData.count),
      name: "stream",
      fileName: "stream.txt",
      mimeType: "text/plain"
    )

    XCTAssertEqual(formData.contentLength, UInt64(testData.count))
  }

  func testEmptyFormData() throws {
    let formData = MultipartFormData()

    // Encoding empty form data should succeed
    let encoded = try formData.encode()
    XCTAssertEqual(encoded.count, 0)
  }

  func testLargeData() throws {
    let formData = MultipartFormData()

    // Create 1MB of data
    let largeData = Data(repeating: 0xFF, count: 1024 * 1024)
    formData.append(largeData, withName: "large", fileName: "large.bin", mimeType: "application/octet-stream")

    let encoded = try formData.encode()
    XCTAssertGreaterThan(encoded.count, largeData.count)
  }

  func testWriteEncodedDataToFile() throws {
    let formData = MultipartFormData()
    let testData = "Test file write".data(using: .utf8)!

    formData.append(testData, withName: "file", fileName: "test.txt", mimeType: "text/plain")

    let tempDir = FileManager.default.temporaryDirectory
    let outputURL = tempDir.appendingPathComponent("output-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    try formData.writeEncodedData(to: outputURL)

    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

    let written = try Data(contentsOf: outputURL)
    XCTAssertGreaterThan(written.count, 0)
  }

  func testWriteToExistingFile() throws {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(testData, withName: "file")

    let tempDir = FileManager.default.temporaryDirectory
    let outputURL = tempDir.appendingPathComponent("existing-\(UUID().uuidString).txt")

    // Create existing file
    try testData.write(to: outputURL)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    // Should throw because file already exists
    XCTAssertThrowsError(try formData.writeEncodedData(to: outputURL))
  }

  func testWriteToNonFileURL() throws {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(testData, withName: "file")

    let httpURL = URL(string: "https://example.com/output.txt")!

    // Should throw because URL is not a file URL
    XCTAssertThrowsError(try formData.writeEncodedData(to: httpURL))
  }

  func testMultipartFormDataErrorUnderlyingError() {
    let nsError = NSError(domain: "test", code: 1, userInfo: nil)
    let error = MultipartFormDataError.inputStreamReadFailed(error: nsError)

    XCTAssertNotNil(error.underlyingError)
    XCTAssertNil(error.url)
  }

  func testMultipartFormDataErrorURL() {
    let url = URL(fileURLWithPath: "/test/file.txt")
    let error = MultipartFormDataError.bodyPartFileNotReachable(at: url)

    XCTAssertNotNil(error.url)
    XCTAssertNil(error.underlyingError)
  }

  func testContentLengthCalculation() {
    let formData = MultipartFormData()
    let data1 = "Part 1".data(using: .utf8)!
    let data2 = "Part 2".data(using: .utf8)!

    formData.append(data1, withName: "part1")
    formData.append(data2, withName: "part2")

    let expectedLength = UInt64(data1.count + data2.count)
    XCTAssertEqual(formData.contentLength, expectedLength)
  }
}
