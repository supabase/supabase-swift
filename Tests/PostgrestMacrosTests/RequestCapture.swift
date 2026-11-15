//
//  RequestCapture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import HTTPTypesFoundation
import PostgrestMacros
import TestHelpers

struct RequestCapture {
  let client: PostgrestClient
  private let transport: RecordingTransport

  init(body: String = "[]") throws {
    let transport = RecordingTransport { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        Data(body.utf8)
      )
    }
    self.transport = transport
    client = try PostgrestClient(
      configuration: .init(
        url: URL(string: "https://example.supabase.co")!,
        headers: [.xClientInfo: "postgrest-swift/test"],
        http: .init(transport: transport)
      )
    )
  }

  private var captured: HTTPTypes.HTTPRequest? { transport.requests.last?.head }

  var query: String? {
    guard let query = captured?.url?.query else { return nil }
    return query.removingPercentEncoding ?? query
  }

  var path: String? { captured?.url?.path }

  var prefer: String? { captured?.headerFields[HTTPField.Name("Prefer")!] }

  var bodyString: String? {
    transport.requests.last?.body.map { String(decoding: $0, as: UTF8.self) }
  }
}
