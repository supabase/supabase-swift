//
//  ObjectKey.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation

/// One object path, normalized and ready for a URL or a JSON body.
///
/// Storage rejects a leading `/`, an empty segment and `..`, so every path is normalized or
/// refused here, once, instead of in each route: leading and trailing `/` are stripped, runs of
/// `/` collapse, and a `.` or `..` segment throws ``StorageError`` with kind `invalidRequest`
/// (a URL parser would fold it away and silently change the key).
struct ObjectKey: Hashable, Sendable {
  /// The path segments, not percent-encoded.
  let segments: [String]

  /// The normalized path, `folder/file.png`, as sent in JSON bodies and echoed in responses.
  var path: String { segments.joined(separator: "/") }

  /// The normalized path with each segment percent-encoded, for the path of a URL.
  var encoded: String { segments.map(Self.encode).joined(separator: "/") }

  /// Normalizes an object path. An empty path is refused: every object route needs a key.
  init(_ path: String) throws {
    try self.init(prefix: path)
    guard !segments.isEmpty else {
      throw StorageError(kind: .invalidRequest, message: "An object path must not be empty.")
    }
  }

  /// Normalizes a listing prefix, which may be empty to mean the bucket root.
  init(prefix path: String) throws {
    let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    if let dots = segments.first(where: { $0 == "." || $0 == ".." }) {
      throw StorageError(
        kind: .invalidRequest,
        message: "An object path must not contain a '\(dots)' segment: '\(path)'.")
    }
    self.segments = segments
  }

  /// What stays literal inside one segment: `.urlPathAllowed` minus the separator and minus
  /// `+`, which some proxies decode as a space.
  private static let allowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed
    set.remove(charactersIn: "+/")
    return set
  }()

  /// Percent-encodes one segment. Bucket ids go through this for the one segment they occupy.
  static func encode(_ segment: String) -> String {
    segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
  }
}
