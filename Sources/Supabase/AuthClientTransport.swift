//
//  AuthClientTransport.swift
//  Supabase
//
//  Created by Guilherme Souza on 05/08/25.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct AuthClientTransport: ClientTransport {
  let transport: any ClientTransport
  let accessToken: @Sendable () async -> String?

  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if let token = await accessToken() {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await transport.send(request, body: body, baseURL: baseURL, operationID: operationID)
  }
}
