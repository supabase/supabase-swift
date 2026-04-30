import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Builder for constructing multipart/form-data payloads
@available(macOS 10.15.4, *)
struct MultipartBuilder {
  let boundary: String
  private var parts: [Part] = []

  var contentType: String { "multipart/form-data; boundary=\(boundary)" }

  enum Part {
    case text(name: String, value: String)
    case data(name: String, data: Data, fileName: String?, mimeType: String?)
    case file(name: String, fileURL: URL, fileName: String?, mimeType: String?)
  }

  init(boundary: String = "----sb-\(UUID().uuidString)") {
    self.boundary = boundary
  }

  /// Add a text field to the multipart payload
  func addText(name: String, value: String) -> MultipartBuilder {
    var builder = self
    builder.parts.append(.text(name: name, value: value))
    return builder
  }

  /// Add an optional text field (only adds if value is non-nil)
  func addOptionalText(name: String, value: String?) -> MultipartBuilder {
    if let value = value {
      return addText(name: name, value: value)
    }
    return self
  }

  /// Add a data field to the multipart payload.
  func addData(
    name: String,
    data: Data,
    fileName: String? = nil,
    mimeType: String? = nil
  ) -> MultipartBuilder {
    var builder = self
    builder.parts.append(.data(name: name, data: data, fileName: fileName, mimeType: mimeType))
    return builder
  }

  /// Add a file field to the multipart payload (loads entire file into memory)
  func addFile(
    name: String,
    fileURL: URL,
    fileName: String? = nil,
    mimeType: String? = nil
  ) -> MultipartBuilder {
    var builder = self
    builder.parts.append(
      .file(name: name, fileURL: fileURL, fileName: fileName, mimeType: mimeType))
    return builder
  }

  /// Build the multipart payload in memory
  /// - Note: Only suitable for small payloads. Use `buildToTempFile()` for large files.
  /// - Returns: Complete multipart body data
  func buildInMemory() throws -> Data {
    guard !parts.isEmpty else { return Data() }

    var body = Data()

    for part in parts {
      switch part {
      case .text(let name, let value):
        body.append(textPart(name: name, value: value))
      case .data(let name, let data, let fileName, let mimeType):
        body.append(dataPart(name: name, data: data, fileName: fileName, mimeType: mimeType))
      case .file(let name, let fileURL, let fileName, let mimeType):
        body.append(
          try filePart(name: name, fileURL: fileURL, fileName: fileName, mimeType: mimeType)
        )
      }
    }

    body.append(closingBoundary())
    return body
  }

  /// Build the multipart payload to a temporary file
  /// - Note: Streams file contents to avoid memory pressure on large files
  /// - Returns: URL of temporary file containing multipart body
  func buildToTempFile() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent(UUID().uuidString)

    // Create temp file
    guard FileManager.default.createFile(atPath: tempFile.path, contents: nil) else {
      throw MultipartBuilderError.createTempFileFailed
    }

    var didReturnTempFile = false
    defer {
      if !didReturnTempFile {
        try? FileManager.default.removeItem(at: tempFile)
      }
    }

    guard let handle = FileHandle(forWritingAtPath: tempFile.path) else {
      throw MultipartBuilderError.openTempFileFailed
    }

    defer { try? handle.close() }

    guard !parts.isEmpty else {
      didReturnTempFile = true
      return tempFile
    }

    // Write parts
    for part in parts {
      switch part {
      case .text(let name, let value):
        let data = textPart(name: name, value: value)
        try handle.write(contentsOf: data)

      case .data(let name, let data, let fileName, let mimeType):
        try handle.write(contentsOf: partHeader(name: name, fileName: fileName, mimeType: mimeType))
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\r\n".utf8))

      case .file(let name, let fileURL, let fileName, let mimeType):
        // Write file part header
        let header = partHeader(
          name: name,
          fileName: fileName ?? fileURL.lastPathComponent,
          mimeType: mimeType
        )
        try handle.write(contentsOf: header)

        // Stream file contents in chunks
        try streamFile(from: fileURL, to: handle)

        // Write trailing newline
        try handle.write(contentsOf: Data("\r\n".utf8))
      }
    }

    // Write closing boundary
    try handle.write(contentsOf: closingBoundary())

    didReturnTempFile = true
    return tempFile
  }

  // MARK: - Private Helpers

  private func textPart(name: String, value: String) -> Data {
    var data = Data()
    data.append(Data("--\(boundary)\r\n".utf8))
    data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
    data.append(Data("\r\n".utf8))
    data.append(Data("\(value)\r\n".utf8))
    return data
  }

  private func dataPart(
    name: String,
    data: Data,
    fileName: String?,
    mimeType: String?
  ) -> Data {
    var partData = Data()
    partData.append(partHeader(name: name, fileName: fileName, mimeType: mimeType))
    partData.append(data)
    partData.append(Data("\r\n".utf8))
    return partData
  }

  private func filePart(
    name: String,
    fileURL: URL,
    fileName: String?,
    mimeType: String?
  ) throws -> Data {
    var data = Data()

    data.append(
      partHeader(name: name, fileName: fileName ?? fileURL.lastPathComponent, mimeType: mimeType)
    )

    let fileData = try Data(contentsOf: fileURL)
    data.append(fileData)

    data.append(Data("\r\n".utf8))

    return data
  }

  private func partHeader(name: String, fileName: String?, mimeType: String?) -> Data {
    var header = Data()
    header.append(Data("--\(boundary)\r\n".utf8))
    var disposition = "Content-Disposition: form-data; name=\"\(name)\""
    if let fileName {
      disposition.append("; filename=\"\(fileName)\"")
    }
    header.append(Data("\(disposition)\r\n".utf8))

    if let mimeType = mimeType {
      header.append(Data("Content-Type: \(mimeType)\r\n".utf8))
    }

    header.append(Data("\r\n".utf8))
    return header
  }

  private func closingBoundary() -> Data {
    return Data("--\(boundary)--\r\n".utf8)
  }

  private func streamFile(from url: URL, to handle: FileHandle) throws {
    guard let input = InputStream(url: url) else {
      throw MultipartBuilderError.openInputStreamFailed
    }

    input.open()
    defer { input.close() }

    let bufferSize = 64 * 1024  // 64KB chunks
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while input.hasBytesAvailable {
      let bytesRead = input.read(&buffer, maxLength: bufferSize)
      if bytesRead > 0 {
        let data = Data(bytes: buffer, count: bytesRead)
        try handle.write(contentsOf: data)
      } else if bytesRead < 0 {
        throw MultipartBuilderError.readInputStreamFailed(underlying: input.streamError)
      }
    }
  }
}

// MARK: - Errors

/// Errors that can occur during multipart building operations.
public enum MultipartBuilderError: LocalizedError {
  case createTempFileFailed
  case openTempFileFailed
  case openInputStreamFailed
  case readInputStreamFailed(underlying: (any Error)?)

  public var errorDescription: String? {
    switch self {
    case .createTempFileFailed:
      return "Failed to create temp file"
    case .openTempFileFailed:
      return "Failed to create temp file"
    case .openInputStreamFailed:
      return "Failed to open file for reading"
    case .readInputStreamFailed:
      return "Error reading file"
    }
  }
}
