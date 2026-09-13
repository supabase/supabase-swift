//
//  QueryEncoding.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 22/08/26.
//
package import Foundation

/// Percent-encoding for URL query items.
///
/// `URLComponents.queryItems` cannot be used for this. Its encoding leaves `+`
/// literal, and a server that form-decodes the query string reads a literal
/// `+` as a space — so `received_at=gt.2023-03-23T15:50:30.511743+00:00`
/// arrives with a space where the UTC offset should be, and a `+16505555555`
/// phone number loses its country code. Neither fails loudly; both just match
/// the wrong rows.
///
/// So everything RFC 3986 reserves is escaped instead, with two exceptions:
/// `?` and `/`, which section 3.4 explicitly permits inside a query. Leaving
/// those alone keeps a URL passed as a parameter value readable in a log
/// without changing how it parses.
package enum QueryEncoding {
  private static let itemAllowed: CharacterSet = {
    let generalDelimitersToEncode = ":#[]@"  // "?" and "/" stay, per RFC 3986 section 3.4
    let subDelimitersToEncode = "!$&'()*+,;="
    let encodableDelimiters = CharacterSet(
      charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

    return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
  }()

  /// Encodes one query item name or value.
  package static func item(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: itemAllowed) ?? value
  }

  /// Renders query items into a percent-encoded query string.
  ///
  /// Order is preserved and repeated names are kept, because repeated-key
  /// encoding (`?k=a&k=b`) is how list parameters are expressed.
  ///
  /// - Parameter items: The query items, with names and values unescaped.
  /// - Returns: The encoded query string without a leading `?`, or `nil` when
  ///   `items` is empty.
  package static func render(_ items: [URLQueryItem]) -> String? {
    guard !items.isEmpty else { return nil }

    return
      items
      .map { queryItem in
        guard let value = queryItem.value else { return item(queryItem.name) }
        return "\(item(queryItem.name))=\(item(value))"
      }
      .joined(separator: "&")
  }
}
