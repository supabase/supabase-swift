//
//  RequestCapture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation
import PostgrestMacros

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A ``ClientTransport`` backed by a closure, for tests that need to inspect the outgoing request
/// or hand back a response built by hand instead of proxying through `URLSession`.
///
/// A private copy of `TestHelpers`' `ClosureTransport`: `PostgrestMacrosTests` doesn't otherwise
/// depend on `TestHelpers`, and this is the only place that needs it.
private struct ClosureTransport: ClientTransport {
  let handler:
    @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    )

  func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    try await handler(request, body)
  }
}

/// Captures the `HTTPRequest` a typed query produces, so a test can assert on it in its own context.
///
/// A trimmed sibling of `QueryCapture` in `PostgRESTTests`. The two test targets cannot share a
/// helper without a third target, and a macro test needs far less of it than the builder tests do.
struct RequestCapture {
  let client: PostgrestClient
  private let captured = LockIsolated(HTTPTypes.HTTPRequest?.none)
  private let capturedBody = LockIsolated(Data?.none)

  init(body: String = "[]") {
    let captured = self.captured
    let capturedBody = self.capturedBody
    client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      headers: ["X-Client-Info": "postgrest-swift/test"],
      transport: ClosureTransport { request, requestBody in
        captured.setValue(request)
        if let requestBody {
          let data = try await Data(collecting: requestBody, upTo: .max)
          capturedBody.setValue(data)
        }
        return (
          HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
          HTTPBody(Data(body.utf8))
        )
      }
    )
  }

  /// The query string, percent-decoded so assertions read in the spelling PostgREST documents.
  var query: String? {
    guard let query = captured.value?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  /// The path of the captured request's URL, which ends in the relation name.
  var path: String? { captured.value?.url?.path }

  /// The captured request's `Prefer` header, for asserting the full value rather than a substring.
  var prefer: String? { captured.value?.headerFields[HTTPField.Name("Prefer")!] }

  /// The captured request body decoded as UTF-8.
  var bodyString: String? {
    capturedBody.value.map { String(decoding: $0, as: UTF8.self) }
  }
}
