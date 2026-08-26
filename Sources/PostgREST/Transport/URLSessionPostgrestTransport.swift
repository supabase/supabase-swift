//
//  URLSessionPostgrestTransport.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

public import Foundation
import HTTPRuntime
public import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The ``PostgrestTransport`` PostgREST uses when a caller supplies none, backed by `URLSession`.
///
/// Worth conforming through rather than around: a transport that only wants to observe or adjust a
/// request can hold one of these and delegate, which keeps the URL assembly and its encoding rules
/// in one place.
public struct URLSessionPostgrestTransport: PostgrestTransport {
  private let transport: HTTPRuntime.URLSessionTransport

  /// Creates a transport over an existing session.
  ///
  /// - Parameter session: The session to send on. Defaults to `URLSession.shared`.
  public init(session: URLSession = .shared) {
    self.transport = HTTPRuntime.URLSessionTransport(session: session)
  }

  /// Creates a transport over a session built from a configuration.
  ///
  /// This is the seam for a request timeout: set `timeoutIntervalForRequest` on the configuration.
  ///
  /// - Parameter configuration: The configuration to build the session from.
  public init(configuration: URLSessionConfiguration) {
    self.transport = HTTPRuntime.URLSessionTransport(configuration: configuration)
  }

  public func send(
    _ request: HTTPTypes.HTTPRequest, body: Data?
  ) async throws -> (Data, HTTPTypes.HTTPResponse) {
    let response = try await transport.send(
      HTTPRuntime.HTTPRequest(
        method: try postgrestHTTPMethod(from: request.method),
        url: try postgrestRequestURL(from: request),
        headers: postgrestHeaderDictionary(from: request.headerFields),
        body: body.map { .data($0) }
      )
    )

    return (response.body, postgrestHTTPResponse(from: response.head))
  }
}
