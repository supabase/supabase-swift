//
//  PostgrestTransport.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

public import Foundation
public import HTTPTypes

/// Takes over how PostgREST puts a request on the wire.
///
/// Conform to this to add a timeout, inject a header, log, or serve canned responses in a test —
/// the capability today's `fetch:` handler provides. Pass an instance where the client accepts one
/// and nothing else about the query API changes.
///
/// Most conformances only want to observe or adjust a request and then let it go out normally.
/// Wrap ``URLSessionPostgrestTransport`` rather than reimplementing it:
///
/// ```swift
/// struct LoggingTransport: PostgrestTransport {
///   let wrapped = URLSessionPostgrestTransport()
///
///   func send(
///     _ request: HTTPRequest, body: Data?
///   ) async throws -> (Data, HTTPResponse) {
///     print(request.method, request.path ?? "")
///     return try await wrapped.send(request, body: body)
///   }
/// }
/// ```
///
/// ## The request carries its query in `path`
///
/// `HTTPTypes.HTTPRequest` has no `URL`. It carries `scheme`, `authority` and `path`, where `path`
/// is the origin-form target — already percent-encoded, and already including `?` and the query
/// string. A conformance that needs a `URL` should build one by concatenation:
///
/// ```swift
/// guard let scheme = request.scheme,
///   let authority = request.authority,
///   let path = request.path,
///   let url = URL(string: "\(scheme)://\(authority)\(path)")
/// else { throw URLError(.badURL) }
/// ```
///
/// Do not route `path` through `URLComponents.path` or `URLQueryItem` on the way. Those decode and
/// re-encode, and PostgREST relies on an encoding stricter than Foundation's default — a `+` in a
/// timestamp filter comes back as a space, matching the wrong rows.
public protocol PostgrestTransport: Sendable {
  /// Sends a request and returns its response.
  ///
  /// - Parameters:
  ///   - request: The request to send. Its `path` includes the query string.
  ///   - body: The request body, already encoded, or `nil` when there is none.
  /// - Returns: The response body, and the status and header fields that came with it.
  /// - Throws: Any error. It reaches the caller of `execute()` unchanged.
  func send(_ request: HTTPTypes.HTTPRequest, body: Data?) async throws
    -> (Data, HTTPTypes.HTTPResponse)
}
