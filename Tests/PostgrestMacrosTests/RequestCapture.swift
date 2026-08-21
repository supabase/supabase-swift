//
//  RequestCapture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import ConcurrencyExtras
import Foundation
import PostgrestMacros

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the `URLRequest` a typed query produces, so a test can assert on it in its own context.
///
/// A trimmed sibling of `QueryCapture` in `PostgRESTTests`. The two test targets cannot share a
/// helper without a third target, and a macro test needs far less of it than the builder tests do.
struct RequestCapture {
  let client: PostgrestClient
  private let captured = LockIsolated(URLRequest?.none)

  init(body: String = "[]") {
    let captured = self.captured
    client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      headers: ["X-Client-Info": "postgrest-swift/test"],
      fetch: { request in
        captured.setValue(request)
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
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

  /// The captured request body decoded as UTF-8.
  var bodyString: String? {
    captured.value?.httpBody.map { String(decoding: $0, as: UTF8.self) }
  }
}
