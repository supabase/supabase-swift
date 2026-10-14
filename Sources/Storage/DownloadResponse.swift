//
//  DownloadResponse.swift
//  Storage
//
//  Created by Guilherme Souza on 13/10/26.
//

public import Foundation
public import HTTPTypes

/// A downloaded object's body and the response Storage sent with it.
///
/// Returned by ``StorageBucket/download(path:transform:options:progress:)``, where ``body``
/// streams the object.
///
/// The common headers have typed properties. Read any other from ``httpResponse``:
///
/// ```swift
/// let response = try await bucket.download(path: "photo.jpg", transform: ImageTransform(width: 200))
/// let applied = response.httpResponse.headerFields[HTTPField.Name("X-Transformations")!]
/// ```
public struct DownloadResponse: Sendable {
  /// The status and headers Storage sent, e.g. `206 Partial Content` for a ranged download.
  public let httpResponse: HTTPResponse
  /// The object's bytes, streamed as they arrive. It can be read once.
  public let body: HTTPBody

  /// Creates a response, for tests and mocks.
  public init(httpResponse: HTTPResponse, body: HTTPBody) {
    self.httpResponse = httpResponse
    self.body = body
  }

  /// The `Content-Type` Storage serves the object with.
  public var contentType: String? {
    httpResponse.headerFields[.contentType]
  }

  /// The `Content-Length`: the size of the object, or of the requested range. `nil` when Storage
  /// does not send one, as for a transformed image.
  public var contentLength: Int64? {
    httpResponse.headerFields[.contentLength].flatMap { Int64($0) }
  }

  /// The `Content-Range` of a ranged download, e.g. `"bytes 0-1023/4096"`.
  public var contentRange: String? {
    httpResponse.headerFields[.contentRange]
  }

  /// The object's `ETag`, quotes included.
  public var eTag: String? {
    httpResponse.headerFields[.eTag]
  }

  /// When the object was last written.
  public var lastModified: Date? {
    httpResponse.headerFields[.lastModified].flatMap(Self.httpDate)
  }

  /// The `Cache-Control` the object was uploaded with.
  public var cacheControl: String? {
    httpResponse.headerFields[.cacheControl]
  }

  /// Reads the whole body into memory.
  ///
  /// ```swift
  /// let data = try await bucket.download(path: "avatar.png").data()
  /// ```
  ///
  /// - Parameter maxBytes: Throw `HTTPBodyTooLargeError` once more than this many bytes arrive.
  ///   No limit by default.
  /// - Throws: ``StorageError`` with kind `transport` if the network fails while the body
  ///   streams.
  public func data(upTo maxBytes: Int = .max) async throws -> Data {
    try await Data(collecting: body, upTo: maxBytes)
  }

  /// Streams the body to a file, so the object never has to fit in memory. See
  /// `HTTPBody.write(to:)`.
  ///
  /// ```swift
  /// try await bucket.download(path: "video.mp4").write(to: fileURL)
  /// ```
  ///
  /// - Throws: ``StorageError`` with kind `transport` if the network fails while the body
  ///   streams, and the file system's error if `fileURL` cannot be written.
  public func write(to fileURL: URL) async throws {
    try await body.write(to: fileURL)
  }

  /// Parses an IMF-fixdate such as `Tue, 13 Oct 2026 15:00:00 GMT`, the form Storage sends.
  private static func httpDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: string)
  }
}
