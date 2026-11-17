//
//  ObjectKey.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation

/// One object path, as the caller wrote it, ready for a URL or a JSON body.
///
/// Storage judges the key, so nothing is trimmed, collapsed or refused here: `/a//b/` is its own
/// key, and an empty key or a `..` segment gets Storage's own `InvalidKey` answer. Only the URL
/// form is encoded, one segment at a time.
struct ObjectKey: Hashable, Sendable {
  /// The path exactly as the caller passed it, as sent in JSON bodies.
  let path: String

  init(_ path: String) {
    self.path = path
  }

  /// The path with each segment percent-encoded, for the path of a URL. Empty segments stay, so
  /// `a//b/` keeps both slashes.
  var encoded: String {
    path.split(separator: "/", omittingEmptySubsequences: false)
      .map { Self.encode(String($0)) }
      .joined(separator: "/")
  }

  /// What stays literal inside one segment: the RFC 3986 path characters minus `+`, which some
  /// proxies decode as a space. Spelled out because `.urlPathAllowed` differs by platform:
  /// Linux's lacks `;`.
  private static let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*,;=:@")

  /// Percent-encodes one segment. Bucket ids go through this for the one segment they occupy.
  ///
  /// A `.` or `..` segment is fully encoded: libcurl, which `URLSession` uses on Linux, and
  /// `URL.standardized` fold a literal one away and would send a different key. The server
  /// decodes `%2E%2E` back to `..`.
  static func encode(_ segment: String) -> String {
    switch segment {
    case ".": "%2E"
    case "..": "%2E%2E"
    default: segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
  }
}
