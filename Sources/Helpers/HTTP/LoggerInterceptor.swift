//
//  LoggerInterceptor.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
package import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct LoggerInterceptor: HTTPClientInterceptor {
  let logger: Logging.Logger

  package init(logger: Logging.Logger) {
    self.logger = logger
  }

  package func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse {
    let id = UUID().uuidString
    var logger = logger
    logger[metadataKey: "requestID"] = "\(id)"

    let urlRequest = request.urlRequest

    logger.trace(
      """
      Request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
      Body: \(stringify(request.body))
      """
    )

    do {
      let response = try await next(request)
      logger.trace(
        """
        Response: Status code: \(response.statusCode) Content-Length: \(
          response.underlyingResponse.expectedContentLength
        )
        Body: \(stringify(response.data))
        """
      )
      return response
    } catch {
      logger.error("Response: Failure \(error)")
      throw error
    }
  }
}

func stringify(_ data: Data?) -> String {
  guard let data else {
    return "<none>"
  }

  do {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    let prettyData = try JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys]
    )
    return String(data: prettyData, encoding: .utf8) ?? "<failed>"
  } catch {
    return String(data: data, encoding: .utf8) ?? "<failed>"
  }
}
