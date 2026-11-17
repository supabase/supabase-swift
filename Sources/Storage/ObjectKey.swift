//
//  ObjectKey.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation

/// One object path, ready for a URL or a JSON body.
///
/// Storage itself takes any key as written, but the API gateway in front of it rewrites the URL
/// path before Storage sees it: it drops a leading `/`, collapses runs of `/`, and resolves `.` and
/// `..` segments, even percent-encoded ones. So `upload(path: "/a//b.png")` is stored as `a/b.png`,
/// and `upload(path: "d/x/../y.png")` overwrites `d/y.png`.
///
/// This type applies the same rewrite to every path, in URLs and in JSON bodies alike, so the key
/// the SDK reports and sends in a body is the key the gateway lets through. A `.` or `..` segment
/// throws ``StorageError`` with kind `invalidRequest`: the gateway would silently send it to a
/// different key. A trailing `/` is kept, because the gateway keeps it.
struct ObjectKey: Hashable, Sendable {
  /// The path segments, not percent-encoded.
  let segments: [String]

  /// Whether the path ends in `/`. Only meaningful when there is at least one segment.
  let trailingSlash: Bool

  /// The normalized path, `folder/file.png`, as sent in JSON bodies and echoed in responses.
  var path: String { join(segments) }

  /// The normalized path with each segment percent-encoded, for the path of a URL.
  var encoded: String { join(segments.map(Self.encode)) }

  /// Normalizes an object path or a listing prefix. An empty path is sent as is: Storage answers
  /// it with `InvalidKey` on the same route.
  init(_ path: String) throws {
    self.init(lenient: path)
    if let dots = segments.first(where: { $0 == "." || $0 == ".." }) {
      throw StorageError(
        kind: .invalidRequest,
        message: "An object path must not contain a '\(dots)' segment: '\(path)'.")
    }
  }

  /// Normalizes without refusing anything, for ``StorageBucket/publicURL`` which cannot throw:
  /// a `.` or `..` segment is kept and fully percent-encoded, so the URL stays valid and no parser
  /// folds it away; the server then rejects the key.
  init(lenient path: String) {
    segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    trailingSlash = path.hasSuffix("/")
  }

  private func join(_ parts: [String]) -> String {
    let joined = parts.joined(separator: "/")
    return trailingSlash && !parts.isEmpty ? joined + "/" : joined
  }

  /// What stays literal inside one segment: the RFC 3986 path characters minus `+`, which some
  /// proxies decode as a space. Spelled out because `.urlPathAllowed` differs by platform:
  /// Linux's lacks `;`.
  private static let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*,;=:@")

  /// Percent-encodes one segment. Bucket ids go through this for the one segment they occupy.
  static func encode(_ segment: String) -> String {
    switch segment {
    case ".": "%2E"
    case "..": "%2E%2E"
    default: segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
  }
}
