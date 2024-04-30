//
//  LoggerInterceptor.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

package struct LoggerInterceptor: HTTPClientInterceptor {
  let logger: any SupabaseLogger

  package init(logger: any SupabaseLogger) {
    self.logger = logger
  }

  package func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse {
    let id = UUID().uuidString
    logger.verbose(
      """
      Request [\(id)]: \(request.method.rawValue) \(request.url.absoluteString
        .removingPercentEncoding ?? "")
      Body: \(stringfy(request.body))
      """
    )

    do {
      let response = try await next(request)
      logger.verbose(
        """
        Response [\(id)]: Status code: \(response.statusCode) Content-Length: \(
          response.underlyingResponse.expectedContentLength
        )
        Body: \(stringfy(response.data))
        """
      )
      return response
    } catch {
      logger.error("Response [\(id)]: Failure \(error)")
      throw error
    }
  }
}
