//
//  QueryCapture.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import ConcurrencyExtras
import Foundation
import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the `URLRequest` a builder produces, so a test can assert on it in its own context.
///
/// The `Mock.snapshotRequest` helper asserts from inside Mocker's request handler, which runs
/// outside the test's task, so Swift Testing drops the recorded issue and the assertion never
/// fails (SDK-1520). This captures the request instead and leaves the assertion to the test body,
/// where a failure is attributed correctly.
struct QueryCapture {
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

  /// The query string of the captured request, percent-decoded so assertions can be written in
  /// the spelling PostgREST documents rather than in escaped form.
  var query: String? {
    guard let query = captured.value?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  /// The HTTP method of the captured request.
  var httpMethod: String? { captured.value?.httpMethod }

  /// The captured request body decoded as UTF-8.
  var bodyString: String? {
    captured.value?.httpBody.map { String(decoding: $0, as: UTF8.self) }
  }

  /// A header field of the captured request.
  func header(_ name: String) -> String? {
    captured.value?.value(forHTTPHeaderField: name)
  }
}
