//
//  UploadSource.swift
//  Storage
//

import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A `FileHandle` wrapper that closes the underlying handle in `deinit`.
///
/// Guarantees the file descriptor is released regardless of how the owning scope
/// exits — normal return, `throw`, or cooperative Task cancellation.
final class AutoreleasingFileHandle {
  private let handle: FileHandle

  init(forReadingFrom url: URL) throws {
    handle = try FileHandle(forReadingFrom: url)
  }

  func seek(toOffset offset: UInt64) throws {
    try handle.seek(toOffset: offset)
  }

  func read(upToCount count: Int) throws -> Data {
    try handle.read(upToCount: count) ?? Data()
  }

  deinit {
    try? handle.close()
  }
}

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

  /// Opens an `AutoreleasingFileHandle` for reading the file at `.fileURL`, or returns `nil` for `.data`.
  /// The handle closes itself in `deinit` — no manual cleanup required.
  func openForReading() throws -> AutoreleasingFileHandle? {
    guard case .fileURL(let url) = self else { return nil }
    return try AutoreleasingFileHandle(forReadingFrom: url)
  }

  /// Reads a chunk from the source.
  ///
  /// Pass a pre-opened `fileHandle` (from ``openForReading()``) to avoid re-opening the file
  /// on every chunk. When `fileHandle` is `nil` and the source is `.fileURL`, a temporary
  /// `AutoreleasingFileHandle` is created for this call only and released (closed) on return.
  func readChunk(at offset: Int64, maxSize: Int, fileHandle: AutoreleasingFileHandle? = nil)
    throws -> Data
  {
    switch self {
    case .data(let d):
      let start = Int(offset)
      let end = min(start + maxSize, d.count)
      return d[start..<end]
    case .fileURL(let url):
      let handle = try fileHandle ?? AutoreleasingFileHandle(forReadingFrom: url)
      try handle.seek(toOffset: UInt64(offset))
      return try handle.read(upToCount: maxSize)
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
    guard case .fileURL(let url) = self else { return false }
    // If the file size cannot be determined (symlink, network-mounted path, etc.) fall back
    // to true — streaming via a temp file is safe regardless of size, and avoids loading an
    // unknown-size file entirely into memory. Matches the conservative Int.max fallback used
    // in the smart-default TUS-vs-multipart routing in StorageFileAPI.
    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
    return fileSize >= 10 * 1024 * 1024
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
