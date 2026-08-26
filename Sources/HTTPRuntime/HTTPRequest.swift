//
//  HTTPRequest.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation
package import HTTPTypes
import HTTPTypesFoundation

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

/// Assembles an `HTTPRequest` from a base URL, a path template already filled
/// with path parameters, repeated query items, and headers.
///
/// Generated code drives this builder; it never constructs `URLComponents`
/// directly. Query values use repeated-key encoding (`?k=a&k=b`) to match the
/// Smithy/OpenAPI list conventions in the specs.
///
/// The builder does not carry a request body. `HTTPTypes.HTTPRequest` models a
/// head only, so the caller passes the body to `HTTPTransport.send(_:body:)`.
package struct HTTPRequestBuilder: Sendable {
  private let method: HTTPRequest.Method
  private let baseURL: URL
  private let path: String
  private var queryItems: [URLQueryItem] = []
  private var headers: HTTPFields = [:]

  package init(method: HTTPRequest.Method, baseURL: URL, path: String) {
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

  package mutating func setHeader(_ name: HTTPField.Name, _ value: String?) {
    guard let value else { return }
    headers[name] = value
  }

  /// Appends to an existing header value (joined with `separator`, `","` by
  /// default per RFC 7240's `Prefer` directive list) instead of replacing it.
  /// If `value` shares a directive key (the part before `=`) with an existing
  /// component, it replaces that component instead of duplicating it.
  ///
  /// `HTTPFields` matches names case-insensitively on its own, so this no
  /// longer canonicalizes the key by hand.
  ///
  /// - Note: This duplicates `appendOrUpdate(_:value:separator:)` in
  ///   `Sources/Helpers/HTTP/HTTPFields.swift`. HTTPRuntime must not depend on
  ///   Helpers, so the copy stands until Helpers/HTTP retires.
  package mutating func addHeader(_ name: HTTPField.Name, value: String?, separator: String = ",") {
    guard let value else { return }
    if let existing = headers[name] {
      var components = existing.components(separatedBy: separator)
      if let directiveKey = value.split(separator: "=").first,
        let index = components.firstIndex(where: { $0.hasPrefix("\(directiveKey)=") })
      {
        components[index] = value
      } else {
        components.append(value)
      }
      headers[name] = components.joined(separator: separator)
    } else {
      headers[name] = value
    }
  }

  package func build() throws(HTTPRuntimeError) -> HTTPRequest {
    // Compose by string so slashes inside greedy path params ({path+}) are
    // preserved. Generated code percent-encodes individual label values.
    var base = baseURL.absoluteString
    if base.hasSuffix("/") { base.removeLast() }
    let prefixedPath = path.hasPrefix("/") ? path : "/" + path
    guard var components = URLComponents(string: base + prefixedPath) else {
      throw HTTPRuntimeError.invalidURL(base: baseURL, path: path)
    }
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    // The scheme check is load-bearing, not belt-and-braces. A schemeless base
    // URL parses into `URLComponents` and yields a non-nil relative `.url`, so
    // it clears the guards above — and then trips
    // `precondition(schemeRange.location != kCFNotFound)` inside
    // `HTTPTypesFoundation`'s `URL.httpRequestComponents`, aborting the process
    // instead of throwing. `.invalidURL` exists for exactly this input.
    guard let url = components.url, components.scheme != nil else {
      throw HTTPRuntimeError.invalidURL(base: baseURL, path: path)
    }
    return HTTPRequest(method: method, url: url, headerFields: headers)
  }
}
