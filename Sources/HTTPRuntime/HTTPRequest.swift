//
//  HTTPRequest.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation

/// The body of an outgoing request.
///
/// `.file` is the key to streaming large uploads without loading them into
/// memory: `URLSession` streams the file from disk. Multipart requests are
/// assembled by the caller via `MultipartFormData.buildToTempFile()` and
/// passed as `.file`, with the `Content-Type` header set to
/// `MultipartFormData.contentType`.
package enum HTTPBody: Sendable {
  case data(Data)
  case file(URL)
}

/// A fully-resolved HTTP request: absolute URL, headers, and body.
package struct HTTPRequest: Sendable {
  package var method: HTTPMethod
  package var url: URL
  package var headers: [String: String]
  package var body: HTTPBody?

  package init(
    method: HTTPMethod,
    url: URL,
    headers: [String: String] = [:],
    body: HTTPBody? = nil
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
  }
}

/// Assembles an `HTTPRequest` from a base URL, a path template already filled
/// with path parameters, repeated query items, and headers.
///
/// Generated code drives this builder; it never constructs `URLComponents`
/// directly. Query values use repeated-key encoding (`?k=a&k=b`) to match the
/// Smithy/OpenAPI list conventions in the specs.
package struct HTTPRequestBuilder: Sendable {
  private let method: HTTPMethod
  private let baseURL: URL
  private let path: String
  private var queryItems: [URLQueryItem] = []
  private var headers: [String: String] = [:]
  private var body: HTTPBody? = nil

  package init(method: HTTPMethod, baseURL: URL, path: String) {
    self.method = method
    self.baseURL = baseURL
    self.path = path
  }

  package mutating func addQuery(_ name: String, _ value: String?) {
    guard let value else { return }
    queryItems.append(URLQueryItem(name: name, value: value))
  }

  package mutating func addQuery(_ name: String, _ values: [String]?) {
    guard let values else { return }
    for value in values {
      queryItems.append(URLQueryItem(name: name, value: value))
    }
  }

  /// Sets a query item, replacing the first item already using `name` rather
  /// than adding a second one.
  ///
  /// For the parameters a server reads once — `select`, `order`, `limit`,
  /// `offset`, `on_conflict` — where `addQuery` would leave two behind and let
  /// the server pick. Replacement happens in place, so the items around it stay
  /// where they were.
  ///
  /// Only the first match is replaced. A repeated name is usually a list
  /// (`?k=a&k=b`) or, in PostgREST's case, a conjunction on one column;
  /// replacing every match would silently collapse it into a single condition.
  ///
  /// A `nil` value is ignored, matching `addQuery`. Use this to set a value,
  /// not to remove one.
  package mutating func setQuery(_ name: String, _ value: String?) {
    guard let value else { return }
    let item = URLQueryItem(name: name, value: value)
    if let index = queryItems.firstIndex(where: { $0.name == name }) {
      queryItems[index] = item
    } else {
      queryItems.append(item)
    }
  }

  package mutating func setHeader(_ name: String, _ value: String?) {
    guard let value else { return }
    headers[canonicalKey(for: name)] = value
  }

  /// Appends to an existing header value (joined with `separator`, `","` by
  /// default per RFC 7240's `Prefer` directive list) instead of replacing it.
  /// If `value` shares a directive key (the part before `=`) with an existing
  /// component, it replaces that component instead of duplicating it. Header
  /// names are matched case-insensitively per HTTP semantics.
  package mutating func addHeader(_ name: String, value: String?, separator: String = ",") {
    guard let value else { return }
    let key = canonicalKey(for: name)
    if let existing = headers[key] {
      var components = existing.components(separatedBy: separator)
      if let directiveKey = value.split(separator: "=").first,
        let index = components.firstIndex(where: { $0.hasPrefix("\(directiveKey)=") })
      {
        components[index] = value
      } else {
        components.append(value)
      }
      headers[key] = components.joined(separator: separator)
    } else {
      headers[key] = value
    }
  }

  /// Returns the already-stored key matching `name` case-insensitively, if
  /// any, so repeated calls with different casing merge into one header
  /// instead of creating a duplicate entry.
  private func canonicalKey(for name: String) -> String {
    headers.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
  }

  package mutating func setBody(_ body: HTTPBody?) {
    self.body = body
  }

  package func build() throws -> HTTPRequest {
    // Compose by string so slashes inside greedy path params ({path+}) are
    // preserved. Generated code percent-encodes individual label values.
    var base = baseURL.absoluteString
    if base.hasSuffix("/") { base.removeLast() }
    let prefixedPath = path.hasPrefix("/") ? path : "/" + path
    guard var components = URLComponents(string: base + prefixedPath) else {
      throw HTTPError.invalidURL(base: baseURL, path: path)
    }
    // Not `components.queryItems`: that encoding leaves `+` literal, which a
    // form-decoding server reads as a space. See `QueryEncoding`.
    components.percentEncodedQuery = QueryEncoding.render(queryItems)
    guard let url = components.url else {
      throw HTTPError.invalidURL(base: baseURL, path: path)
    }
    return HTTPRequest(method: method, url: url, headers: headers, body: body)
  }
}
