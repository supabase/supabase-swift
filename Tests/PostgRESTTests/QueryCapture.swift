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

struct QueryCapture {
  let client: PostgrestClient
  private let captured = LockIsolated(HTTPTypes.HTTPRequest?.none)
  private let capturedBody = LockIsolated(Data?.none)

  init(
    body: String = "[]",
    status: HTTPTypes.HTTPResponse.Status = .ok,
    responseHeaders: [String: String] = [:],
    headers: [String: String] = ["X-Client-Info": "postgrest-swift/test"],
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    let captured = self.captured
    let capturedBody = self.capturedBody
    let headerFields: HTTPFields = responseHeaders.reduce(into: [.contentType: "application/json"])
    { fields, entry in
      fields[HTTPField.Name(entry.key)!] = entry.value
    }
    client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      headers: headers,
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
            HTTPTypes.HTTPResponse(status: status, headerFields: headerFields),
            HTTPBody(Data(body.utf8))
          )
        }),
      encoder: encoder,
      decoder: decoder
    )
  }

  var query: String? {
    guard let query = captured.value?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  var path: String? { captured.value?.url?.path }

  var httpMethod: String? { captured.value?.method.rawValue }

  var bodyString: String? {
    capturedBody.value.map { String(decoding: $0, as: UTF8.self) }
  }

  var headers: [String: String] {
    guard let fields = captured.value?.headerFields else { return [:] }
    return Dictionary(
      fields.map { ($0.name.canonicalName, $0.value) }, uniquingKeysWith: { "\($0),\($1)" })
  }

  func header(_ name: String) -> String? {
    guard let fieldName = HTTPField.Name(name) else { return nil }
    return captured.value?.headerFields[fieldName]
  }
}
