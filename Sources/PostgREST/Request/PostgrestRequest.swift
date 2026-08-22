//
//  PostgrestRequest.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

public import Foundation
public import HTTPTypes

/// A PostgREST request as a value: method, path, query items, header fields and body, with no
/// client, no transport and no execution attached.
///
/// Building a request is a pure function of this value. Nothing here reaches the network, so the
/// wire format a query produces can be asserted directly instead of recorded as a snapshot of an
/// executed request.
///
/// ```swift
/// var request = PostgrestRequest(method: .get, path: "/todos")
/// request.appendQueryItem(name: "select", value: "*")
/// request.appendQueryItem(name: "is_done", value: "eq.false")
/// #expect(request.renderedQuery == "select=%2A&is_done=eq.false")
/// ```
///
/// ## Query items are an ordered list, not a dictionary
///
/// PostgREST ANDs repeated parameters, so `id=gt.1&id=lt.9` is a single conjunction and both
/// parameters have to survive. ``queryItems`` is therefore an `Array` and ``appendQueryItem(name:value:)``
/// never replaces: a dictionary would silently drop one half of `.gt(\.id, 1).lt(\.id, 9)`.
/// Use ``setQueryItem(name:value:)`` for the parameters that genuinely are single-valued, such as
/// `select` or `on_conflict`.
///
/// ## Percent-encoding happens once, here
///
/// Values are stored exactly as given and escaped only while rendering — see ``renderedQuery``. No
/// caller escapes anything, which is what stops the same value being encoded twice or, worse,
/// inconsistently depending on which method added it.
public struct PostgrestRequest: Hashable, Sendable {
  /// A single query parameter, stored unescaped.
  public struct QueryItem: Hashable, Sendable {
    /// The parameter name, unescaped — a column name, `select`, `order`, and so on.
    public var name: String

    /// The parameter value, unescaped, or `nil` for a parameter that carries no `=`.
    public var value: String?

    /// Creates a query item.
    ///
    /// - Parameters:
    ///   - name: The parameter name, unescaped.
    ///   - value: The parameter value, unescaped, or `nil` for a bare parameter.
    public init(name: String, value: String? = nil) {
      self.name = name
      self.value = value
    }
  }

  /// The HTTP method.
  public var method: HTTPTypes.HTTPRequest.Method

  /// The path this request targets, relative to the PostgREST base URL — `/todos`, `/rpc/sum`.
  ///
  /// Rendered verbatim. It is expected to be a valid, already-encoded URL path; whoever turns a
  /// table or function name into a path owns encoding it, because only they know where one path
  /// component ends and the next begins.
  public var path: String

  /// The query parameters, in the order they were added.
  public var queryItems: [QueryItem]

  /// The header fields to send.
  public var headerFields: HTTPTypes.HTTPFields

  /// The request body, already encoded.
  public var body: Data?

  /// Creates a request.
  ///
  /// - Parameters:
  ///   - method: The HTTP method.
  ///   - path: The path relative to the PostgREST base URL, such as `/todos`.
  ///   - queryItems: The query parameters, unescaped, in the order they should be sent.
  ///   - headerFields: The header fields to send.
  ///   - body: The already-encoded request body.
  public init(
    method: HTTPTypes.HTTPRequest.Method,
    path: String,
    queryItems: [QueryItem] = [],
    headerFields: HTTPTypes.HTTPFields = [:],
    body: Data? = nil
  ) {
    self.method = method
    self.path = path
    self.queryItems = queryItems
    self.headerFields = headerFields
    self.body = body
  }
}

extension PostgrestRequest {
  /// Appends a query parameter, keeping any parameter that already uses the same name.
  ///
  /// This is the right call for filters. PostgREST ANDs repeated parameters, so appending twice
  /// under one name is how a conjunction is expressed on the wire.
  ///
  /// - Parameters:
  ///   - name: The parameter name, unescaped.
  ///   - value: The parameter value, unescaped, or `nil` for a bare parameter.
  public mutating func appendQueryItem(name: String, value: String? = nil) {
    queryItems.append(QueryItem(name: name, value: value))
  }

  /// Sets a query parameter, replacing the first parameter that already uses that name.
  ///
  /// This is the right call for the parameters PostgREST reads only once — `select`, `order`,
  /// `limit`, `offset`, `on_conflict`, `columns`. Replacing in place rather than removing and
  /// appending keeps the surrounding parameters where they were.
  ///
  /// - Parameters:
  ///   - name: The parameter name, unescaped.
  ///   - value: The parameter value, unescaped, or `nil` for a bare parameter.
  public mutating func setQueryItem(name: String, value: String? = nil) {
    let item = QueryItem(name: name, value: value)
    if let index = queryItems.firstIndex(where: { $0.name == name }) {
      queryItems[index] = item
    } else {
      queryItems.append(item)
    }
  }

  /// The values sent under a parameter name, in order.
  ///
  /// - Parameter name: The unescaped parameter name to look for.
  /// - Returns: Every value stored under `name`, unescaped. Empty when the parameter is absent.
  public func queryValues(for name: String) -> [String?] {
    queryItems.lazy.filter { $0.name == name }.map(\.value)
  }
}

extension PostgrestRequest {
  /// The percent-encoded query string, without a leading `?`.
  ///
  /// Empty when there are no query items. This is the one place ``queryItems`` gets escaped.
  public var renderedQuery: String {
    queryItems
      .map { item in
        guard let value = item.value else { return escapeQueryComponent(item.name) }
        return "\(escapeQueryComponent(item.name))=\(escapeQueryComponent(value))"
      }
      .joined(separator: "&")
  }

  /// The path and query as they appear on the wire, relative to the PostgREST base URL.
  ///
  /// - Parameter basePath: The base URL's own path, prefixed to ``path``. Pass `""` when the base
  ///   URL has no path of its own.
  /// - Returns: `basePath + path`, followed by `?` and ``renderedQuery`` when there are query items.
  public func renderedPath(prefixedBy basePath: String = "") -> String {
    let query = renderedQuery
    let fullPath = basePath + path
    return query.isEmpty ? fullPath : "\(fullPath)?\(query)"
  }

  /// Renders this request against a base URL.
  ///
  /// - Parameter baseURL: The PostgREST base URL, such as
  ///   `https://project.supabase.co/rest/v1`. Its own path is kept as a prefix.
  /// - Returns: An `HTTPTypes.HTTPRequest` carrying this request's method, header fields and
  ///   rendered path. The body is not part of `HTTPTypes.HTTPRequest` — send ``body`` alongside it.
  public func httpRequest(baseURL: URL) -> HTTPTypes.HTTPRequest {
    var authority = baseURL.host ?? ""
    if let port = baseURL.port {
      authority += ":\(port)"
    }

    return HTTPTypes.HTTPRequest(
      method: method,
      scheme: baseURL.scheme,
      authority: authority,
      path: renderedPath(prefixedBy: baseURL.path),
      headerFields: headerFields
    )
  }
}

/// Percent-encodes one query name or value.
///
/// Everything RFC 3986 calls a reserved character is escaped, except `?` and `/`, which section
/// 3.4 explicitly allows inside a query. That matters more here than it looks: PostgREST puts
/// user data straight into parameter values, so a `&` or `=` left alone would end the parameter
/// early, and a `+` left alone decodes to a space on a server that reads the query as a form body.
///
/// This matches the encoding `Helpers`' `sbURLQueryAllowed` applies on the legacy path, so both
/// paths put the same bytes on the wire.
private func escapeQueryComponent(_ string: String) -> String {
  string.addingPercentEncoding(withAllowedCharacters: .postgrestQueryAllowed) ?? string
}

extension CharacterSet {
  /// `urlQueryAllowed` minus every RFC 3986 reserved character other than `?` and `/`.
  fileprivate static let postgrestQueryAllowed: CharacterSet = {
    let generalDelimitersToEncode = ":#[]@"  // "?" and "/" stay, per RFC 3986 section 3.4
    let subDelimitersToEncode = "!$&'()*+,;="
    let encodableDelimiters = CharacterSet(
      charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

    return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
  }()
}
