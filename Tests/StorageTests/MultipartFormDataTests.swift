import Foundation
import Testing

@testable import Storage

@Suite
struct MultipartFormDataTests {
  @Test
  func boundaryGeneration() {
    let formData = MultipartFormData()
    #expect(!formData.boundary.isEmpty)
    #expect(formData.contentType.contains("multipart/form-data; boundary="))
  }

  @Test
  func appendingData() {
    let formData = MultipartFormData()
    let testData = "Hello World".data(using: .utf8)!

    formData.append(testData, withName: "test", fileName: "test.txt", mimeType: "text/plain")

    #expect(formData.contentLength > 0)
  }

  @Test
  func contentHeaders() {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(
      testData,
      withName: "file",
      fileName: "test.txt",
      mimeType: "text/plain"
    )

    #expect(formData.contentType.hasPrefix("multipart/form-data"))
  }

  @Test
  func customBoundary() {
    let customBoundary = "test-boundary-12345"
    let formData = MultipartFormData(boundary: customBoundary)

    #expect(formData.boundary == customBoundary)
    #expect(formData.contentType.contains(customBoundary))
  }

  @Test
  func appendDataWithoutFileName() {
    let formData = MultipartFormData()
    let testData = "Test data".data(using: .utf8)!

    formData.append(testData, withName: "field")

    #expect(formData.contentLength > 0)
  }

  @Test
  func multipleAppends() {
    let formData = MultipartFormData()
    let data1 = "First".data(using: .utf8)!
    let data2 = "Second".data(using: .utf8)!

    formData.append(data1, withName: "field1", fileName: "file1.txt", mimeType: "text/plain")
    formData.append(data2, withName: "field2", fileName: "file2.txt", mimeType: "text/plain")

    #expect(formData.contentLength == UInt64(data1.count + data2.count))
  }

  @Test
  func encodeFormData() throws {
    let formData = MultipartFormData()
    let testData = "Test content".data(using: .utf8)!

    formData.append(testData, withName: "file", fileName: "test.txt", mimeType: "text/plain")

    let encoded = try formData.encode()
    #expect(encoded.count > 0)

    // Verify encoded data contains boundary
    let encodedString = String(data: encoded, encoding: .utf8)
    #expect(encodedString != nil)
    #expect(encodedString!.contains(formData.boundary))
  }

  @Test
  func appendFileURL() throws {
    let formData = MultipartFormData()

    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).txt")
    let testContent = "File content".data(using: .utf8)!

    try testContent.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    formData.append(fileURL, withName: "upload")

    #expect(formData.contentLength > 0)
  }

  @Test
  func appendFileURLWithCustomMetadata() throws {
    let formData = MultipartFormData()

    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("custom-\(UUID().uuidString).json")
    let testContent = #"{"key": "value"}"#.data(using: .utf8)!

    try testContent.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    formData.append(
      fileURL, withName: "data", fileName: "custom.json", mimeType: "application/json")

    #expect(formData.contentLength > 0)
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test
    func appendInvalidFileURL() {
      let formData = MultipartFormData()
      let invalidURL = URL(fileURLWithPath: "/nonexistent/path/file.txt")

      formData.append(invalidURL, withName: "file")

      // Should fail during encoding
      #expect(throws: (any Error).self) {
        try formData.encode()
      }
    }

    @Test
    func appendNonFileURL() {
      let formData = MultipartFormData()
      let httpURL = URL(string: "https://example.com/file.txt")!

      formData.append(httpURL, withName: "file", fileName: "file.txt", mimeType: "text/plain")

      // Should fail during encoding
      #expect(throws: (any Error).self) {
        try formData.encode()
      }
    }

    @Test
    func appendDirectory() throws {
      let formData = MultipartFormData()

      // Use a known directory
      let dirURL = FileManager.default.temporaryDirectory

      formData.append(dirURL, withName: "dir")

      // Should fail during encoding
      #expect(throws: (any Error).self) {
        try formData.encode()
      }
    }
  #endif

  @Test
  func appendInputStream() {
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

    #expect(formData.contentLength == UInt64(testData.count))
  }

  @Test
  func emptyFormData() throws {
    let formData = MultipartFormData()

    // Encoding empty form data should succeed
    let encoded = try formData.encode()
    #expect(encoded.count == 0)
  }

  @Test
  func largeData() throws {
    let formData = MultipartFormData()

    // Create 1MB of data
    let largeData = Data(repeating: 0xFF, count: 1024 * 1024)
    formData.append(
      largeData, withName: "large", fileName: "large.bin", mimeType: "application/octet-stream")

    let encoded = try formData.encode()
    #expect(encoded.count > largeData.count)
  }

  @Test
  func writeEncodedDataToFile() throws {
    let formData = MultipartFormData()
    let testData = "Test file write".data(using: .utf8)!

    formData.append(testData, withName: "file", fileName: "test.txt", mimeType: "text/plain")

    let tempDir = FileManager.default.temporaryDirectory
    let outputURL = tempDir.appendingPathComponent("output-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    try formData.writeEncodedData(to: outputURL)

    #expect(FileManager.default.fileExists(atPath: outputURL.path))

    let written = try Data(contentsOf: outputURL)
    #expect(written.count > 0)
  }

  @Test
  func writeToExistingFile() throws {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(testData, withName: "file")

    let tempDir = FileManager.default.temporaryDirectory
    let outputURL = tempDir.appendingPathComponent("existing-\(UUID().uuidString).txt")

    // Create existing file
    try testData.write(to: outputURL)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    // Should throw because file already exists
    #expect(throws: (any Error).self) {
      try formData.writeEncodedData(to: outputURL)
    }
  }

  @Test
  func writeToNonFileURL() throws {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(testData, withName: "file")

    let httpURL = URL(string: "https://example.com/output.txt")!

    // Should throw because URL is not a file URL
    #expect(throws: (any Error).self) {
      try formData.writeEncodedData(to: httpURL)
    }
  }

  @Test
  func multipartFormDataErrorUnderlyingError() {
    let nsError = NSError(domain: "test", code: 1, userInfo: nil)
    let error = MultipartFormDataError.inputStreamReadFailed(error: nsError)

    #expect(error.underlyingError != nil)
    #expect(error.url == nil)
  }

  @Test
  func multipartFormDataErrorURL() {
    let url = URL(fileURLWithPath: "/test/file.txt")
    let error = MultipartFormDataError.bodyPartFileNotReachable(at: url)

    #expect(error.url != nil)
    #expect(error.underlyingError == nil)
  }

  @Test
  func contentLengthCalculation() {
    let formData = MultipartFormData()
    let data1 = "Part 1".data(using: .utf8)!
    let data2 = "Part 2".data(using: .utf8)!

    formData.append(data1, withName: "part1")
    formData.append(data2, withName: "part2")

    let expectedLength = UInt64(data1.count + data2.count)
    #expect(formData.contentLength == expectedLength)
  }
}
