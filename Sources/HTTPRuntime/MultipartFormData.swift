//
//  MultipartFormData.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
import Foundation

/// Builds a `multipart/form-data` body by streaming its parts onto a temporary
/// file, so large file parts never load fully into memory. The resulting file
/// is then uploaded with `URLSession.upload(for:fromFile:)`.
///
/// This is the runtime's answer to "streaming multipart upload of large files
/// without loading into memory": file parts are copied chunk-by-chunk to the
/// staging file.
public struct MultipartFormData: Sendable {
  public struct Part: Sendable {
    public enum Source: Sendable {
      case data(Data)
      case file(URL)
    }
    public var name: String
    public var filename: String?
    public var contentType: String?
    public var source: Source

    public init(name: String, filename: String? = nil, contentType: String? = nil, source: Source) {
      self.name = name
      self.filename = filename
      self.contentType = contentType
      self.source = source
    }
  }

  public let boundary: String
  public private(set) var parts: [Part]

  public init(boundary: String = "Boundary-\(UUID().uuidString)", parts: [Part] = []) {
    self.boundary = boundary
    self.parts = parts
  }

  public mutating func append(_ part: Part) {
    parts.append(part)
  }

  public var contentType: String {
    "multipart/form-data; boundary=\(boundary)"
  }

  /// Streams all parts to a temporary file and returns its URL. The caller is
  /// responsible for deleting the file after the upload completes.
  public func writeToTemporaryFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("multipart-\(UUID().uuidString).tmp")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    func write(_ string: String) throws {
      try handle.write(contentsOf: Data(string.utf8))
    }

    for part in parts {
      try write("--\(boundary)\r\n")
      var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
      if let filename = part.filename {
        disposition += "; filename=\"\(filename)\""
      }
      try write(disposition + "\r\n")
      if let contentType = part.contentType {
        try write("Content-Type: \(contentType)\r\n")
      }
      try write("\r\n")

      switch part.source {
      case .data(let data):
        try handle.write(contentsOf: data)
      case .file(let fileURL):
        let reader = try FileHandle(forReadingFrom: fileURL)
        defer { try? reader.close() }
        // Copy in bounded chunks so a large file never fully buffers.
        while case let chunk = reader.readData(ofLength: 64 * 1024), !chunk.isEmpty {
          try handle.write(contentsOf: chunk)
        }
      }
      try write("\r\n")
    }
    try write("--\(boundary)--\r\n")
    return url
  }
}
