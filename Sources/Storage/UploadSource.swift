//
//  UploadSource.swift
//  Storage
//

import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum UploadSource: Sendable {
  case data(Data)
  case fileURL(URL)

  // MARK: - TUS chunked streaming

  func totalBytes() throws -> Int64 {
    switch self {
    case .data(let d):
      return Int64(d.count)
    case .fileURL(let url):
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let size = attrs[.size] as? Int64 else {
        throw StorageError(message: "Cannot determine file size", errorCode: .unknown)
      }
      return size
    }
  }

  func readChunk(at offset: Int64, maxSize: Int) throws -> Data {
    switch self {
    case .data(let d):
      let start = Int(offset)
      let end = min(start + maxSize, d.count)
      return d[start..<end]
    case .fileURL(let url):
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(offset))
      return try handle.read(upToCount: maxSize) ?? Data()
    }
  }

  // MARK: - Multipart body building

  func append(
    to builder: MultipartBuilder,
    withPath path: String,
    options: FileOptions
  ) -> MultipartBuilder {
    var builder = builder.addText(name: "cacheControl", value: options.cacheControl)

    if let metadata = options.metadata {
      builder = builder.addText(
        name: "metadata",
        value: String(data: encodeMetadata(metadata), encoding: .utf8) ?? ""
      )
    }

    switch self {
    case .data(let data):
      return builder.addData(
        name: "",
        data: data,
        fileName: path.fileName,
        mimeType: options.contentType ?? mimeType(forPathExtension: path.pathExtension)
      )
    case .fileURL(let url):
      return builder.addFile(
        name: "",
        fileURL: url,
        fileName: url.lastPathComponent,
        mimeType: options.contentType ?? mimeType(forPathExtension: url.pathExtension)
      )
    }
  }

  var usesTempFileUpload: Bool {
    get throws {
      guard case .fileURL(let url) = self else { return false }
      let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      return fileSize >= 10 * 1024 * 1024
    }
  }

  func defaultOptions() -> FileOptions {
    switch self {
    case .data:
      return defaultFileOptions
    case .fileURL:
      var options = defaultFileOptions
      options.contentType = nil
      return options
    }
  }
}
