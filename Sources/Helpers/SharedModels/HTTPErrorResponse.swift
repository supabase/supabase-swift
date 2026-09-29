//
//  HTTPErrorResponse.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

public import Foundation
public import HTTPTypes

/// The HTTP response that produced a ``SupabaseError``.
///
/// Every module error that came from a server round trip carries one of these in its
/// `response` property, so the status, headers, raw body and Supabase request id are
/// available without re-running the request.
///
/// ```swift
/// } catch let error as any SupabaseError {
///   if let response = error.response {
///     print(response.statusCode, response.requestID ?? "no request id")
///   }
/// }
/// ```
public struct HTTPErrorResponse: Sendable, Hashable {
  /// The HTTP status code, e.g. `404`.
  public var statusCode: Int

  /// Every response header. Import `HTTPTypes` to spell header names.
  public var headers: HTTPFields

  /// The raw response body. Empty when the server sent none.
  public var body: Data

  /// The `sb-request-id` header Supabase attaches to every response through its API gateway.
  ///
  /// Quote this value when contacting Supabase support. `nil` on self-hosted stacks that do not
  /// set the header.
  public var requestID: String? {
    headers[.sbRequestID]
  }

  /// Creates a response summary.
  public init(statusCode: Int, headers: HTTPFields, body: Data) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }

  /// Summarizes a response head and the body that came with it.
  package init(_ response: HTTPResponse, body: Data) {
    self.init(statusCode: response.status.code, headers: response.headerFields, body: body)
  }
}

extension HTTPField.Name {
  /// `sb-request-id`, the request id Supabase's API gateway assigns to every response.
  public static let sbRequestID = HTTPField.Name("sb-request-id")!
}
