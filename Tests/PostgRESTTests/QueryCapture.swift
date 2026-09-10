//
//  QueryCapture.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation
import PostgREST
import TestHelpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the `HTTPRequest` a builder produces, so a test can assert on it in its own context.
///
/// The `Mock.snapshotRequest` helper asserts from inside Mocker's request handler, which runs
/// outside the test's task, so Swift Testing drops the recorded issue and the assertion never
/// fails (SDK-1520). This captures the request instead and leaves the assertion to the test body,
/// where a failure is attributed correctly.
struct QueryCapture {
  let client: PostgrestClient
  private let captured = LockIsolated(HTTPTypes.HTTPRequest?.none)
  private let capturedBody = LockIsolated(Data?.none)

  /// - Parameters:
  ///   - body: The response body to hand back to every request.
  ///   - responseHeaders: Extra response header fields, merged over `Content-Type`. Use this to
  ///     stub the `Content-Range` header a count request reads its total from.
  init(body: String = "[]", responseHeaders: [String: String] = [:]) {
    let captured = self.captured
    let capturedBody = self.capturedBody
    let headerFields: HTTPFields = responseHeaders.reduce(into: [.contentType: "application/json"])
    { fields, entry in
      fields[HTTPField.Name(entry.key)!] = entry.value
    }
    client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      headers: ["X-Client-Info": "postgrest-swift/test"],
      transport: ClosureTransport { request, requestBody in
        captured.setValue(request)
        let data: Data? =
          if let requestBody {
            try await Data(collecting: requestBody, upTo: .max)
          } else {
            nil
          }
        capturedBody.setValue(data)
        return (
          HTTPTypes.HTTPResponse(status: .ok, headerFields: headerFields),
          HTTPBody(Data(body.utf8))
        )
      }
    )
  }

  /// The query string of the captured request, percent-decoded so assertions can be written in
  /// the spelling PostgREST documents rather than in escaped form.
  var query: String? {
    guard let query = captured.value?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  /// The path of the captured request's URL, which ends in the relation name.
  var path: String? { captured.value?.url?.path }

  /// The HTTP method of the captured request.
  var httpMethod: String? { captured.value?.method.rawValue }

  /// The captured request body decoded as UTF-8.
  var bodyString: String? {
    capturedBody.value.map { String(decoding: $0, as: UTF8.self) }
  }

  /// A header field of the captured request.
  func header(_ name: String) -> String? {
    guard let fieldName = HTTPField.Name(name) else { return nil }
    return captured.value?.headerFields[fieldName]
  }
}
