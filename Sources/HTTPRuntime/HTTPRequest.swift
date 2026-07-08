//
//  HTTPRequest.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
import Foundation

/// The body of an outgoing request.
///
/// `.file` is the key to streaming large uploads without loading them into
/// memory: `URLSession` streams the file from disk. `.multipart` assembles a
/// `multipart/form-data` body onto a temporary file and then uploads that file,
/// so even large multipart parts never materialize fully in memory.
public enum HTTPBody: Sendable {
  case none
  case data(Data)
  case file(URL)
  case multipart(MultipartFormData)
}

/// A fully-resolved HTTP request: absolute URL, headers, and body.
public struct HTTPRequest: Sendable {
  public var method: HTTPMethod
  public var url: URL
  public var headers: [String: String]
  public var body: HTTPBody

  public init(
    method: HTTPMethod,
    url: URL,
    headers: [String: String] = [:],
    body: HTTPBody = .none
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
public struct HTTPRequestBuilder: Sendable {
  public let method: HTTPMethod
  private let baseURL: URL
  private let path: String
  private var queryItems: [URLQueryItem] = []
  private var headers: [String: String] = [:]
  private var body: HTTPBody = .none

  public init(method: HTTPMethod, baseURL: URL, path: String) {
    self.method = method
    self.baseURL = baseURL
    self.path = path
  }

  public mutating func addQuery(_ name: String, _ value: String?) {
    guard let value else { return }
    queryItems.append(URLQueryItem(name: name, value: value))
  }

  public mutating func addQuery(_ name: String, _ values: [String]?) {
    guard let values else { return }
    for value in values {
      queryItems.append(URLQueryItem(name: name, value: value))
    }
  }

  public mutating func setHeader(_ name: String, _ value: String?) {
    guard let value else { return }
    headers[name] = value
  }

  public mutating func setBody(_ body: HTTPBody) {
    self.body = body
  }

  public func build() throws -> HTTPRequest {
    // Compose by string so slashes inside greedy path params ({path+}) are
    // preserved. Generated code percent-encodes individual label values.
    var base = baseURL.absoluteString
    if base.hasSuffix("/") { base.removeLast() }
    let prefixedPath = path.hasPrefix("/") ? path : "/" + path
    guard var components = URLComponents(string: base + prefixedPath) else {
      throw HTTPError.invalidURL(base: baseURL, path: path)
    }
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    guard let url = components.url else {
      throw HTTPError.invalidURL(base: baseURL, path: path)
    }
    return HTTPRequest(method: method, url: url, headers: headers, body: body)
  }
}
