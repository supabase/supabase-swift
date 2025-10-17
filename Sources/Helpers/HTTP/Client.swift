//
//  Client.swift
//  Supabase
//
//  Created by Guilherme Souza on 17/10/25.
//

import Foundation
import HTTPClient
import HTTPTypesFoundation

extension Client: HTTPClientType {
  package func send(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    guard let httpRequest = request.urlRequest.httpRequest else {
      throw URLError(.badURL)
    }

    let (response, responseBody) = try await self.send(
      httpRequest,
      body: request.body.map { HTTPBody($0) }
    )

    let data =
      if let responseBody {
        try await Data(collecting: responseBody, upTo: .max)
      } else {
        Data()
      }

    guard let httpResponse = HTTPURLResponse(httpResponse: response, url: request.url) else {
      throw URLError(.badServerResponse)
    }

    return Helpers.HTTPResponse(
      data: data,
      response: httpResponse
    )
  }
}
