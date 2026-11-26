//
//  CatalogTestSupport.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers

@_spi(Experimental) import Storage
@_spi(Experimental) import StorageIceberg

struct Sent: Sendable {
  var request: HTTPRequest
  var body: String?
}

/// A catalog for `bucket` whose requests go to `transport`.
func makeCatalog(bucket: String = "events", transport: ClosureTransport) throws -> IcebergCatalog {
  try StorageClient(
    configuration: StorageClient.Configuration(
      url: URL(string: "http://localhost:54321/storage/v1")!,
      headers: [:],
      http: .init(transport: transport))
  )
  .analytics
  .catalog(bucket: bucket)
}

/// A catalog for `bucket` that records each request in `sent` and answers every one with
/// `status` and the JSON `response`.
func makeCatalog(
  bucket: String = "events",
  sent: LockIsolated<[Sent]> = .init([]),
  status: HTTPResponse.Status = .ok,
  response: String
) throws -> IcebergCatalog {
  try makeCatalog(
    bucket: bucket,
    transport: ClosureTransport { request, body in
      var text: String?
      if let body {
        text = String(decoding: try await Data(collecting: body, upTo: .max), as: UTF8.self)
      }
      sent.withValue { [text] in $0.append(Sent(request: request, body: text)) }
      return (
        HTTPResponse(status: status, headerFields: [.contentType: "application/json"]),
        HTTPBody(Data(response.utf8))
      )
    })
}

/// Whether `text` holds the same JSON value as `expected`, whatever the key order.
func jsonEqual(_ text: String?, _ expected: String) throws -> Bool {
  guard let text else { return false }
  let actual = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
  let wanted = try JSONSerialization.jsonObject(with: Data(expected.utf8)) as? NSDictionary
  return actual != nil && actual == wanted
}
