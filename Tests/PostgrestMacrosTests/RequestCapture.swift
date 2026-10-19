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
      http: .init(
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
            HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
            HTTPBody(Data(body.utf8))
          )
        }))
  }

  var query: String? {
    guard let query = captured.value?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  var path: String? { captured.value?.url?.path }

  var prefer: String? { captured.value?.headerFields[HTTPField.Name("Prefer")!] }

  var bodyString: String? {
    capturedBody.value.map { String(decoding: $0, as: UTF8.self) }
  }
}
