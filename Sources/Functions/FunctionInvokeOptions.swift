//
//  FunctionInvokeOptions.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import Foundation
public import HTTPTypes

/// Per-call settings for an invocation. Every field has a default.
///
/// ```swift
/// let options = FunctionInvokeOptions(
///   method: .get,
///   query: [URLQueryItem(name: "month", value: "2026-09")],
///   region: .euWest1,
///   timeout: .seconds(30)
/// )
/// ```
public struct FunctionInvokeOptions: Sendable, Hashable {
  /// The HTTP method. Defaults to `.post`.
  public var method: HTTPRequest.Method

  /// Headers for this call. They win over ``FunctionsClient/Configuration/headers`` and over the
  /// body's `Content-Type`.
  public var headers: HTTPFields

  /// Query items appended to the function URL.
  public var query: [URLQueryItem]

  /// The region to invoke the function in. Overrides ``FunctionsClient/Configuration/region``.
  public var region: FunctionRegion?

  /// A per-call override for the request timeout. Defaults to the client's
  /// `HTTPClientConfiguration.timeout`, or ``FunctionsClient/requestIdleTimeout``, when `nil`.
  public var timeout: Duration?

  /// Creates options for a function invocation.
  /// - Parameters:
  ///   - method: The HTTP method. Defaults to `.post`.
  ///   - headers: Headers for this call.
  ///   - query: Query items appended to the function URL.
  ///   - region: The region to invoke the function in.
  ///   - timeout: A per-call override for the request timeout.
  public init(
    method: HTTPRequest.Method = .post,
    headers: HTTPFields = [:],
    query: [URLQueryItem] = [],
    region: FunctionRegion? = nil,
    timeout: Duration? = nil
  ) {
    self.method = method
    self.headers = headers
    self.query = query
    self.region = region
    self.timeout = timeout
  }
}
