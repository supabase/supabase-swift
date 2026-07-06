//
//  LoggerInterceptor.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
    return try await SupabaseLoggerTaskLocal.$additionalContext.withValue(merging: [
      "requestID": .string(id)
    ]) {
      let urlRequest = request.urlRequest

      logger.verbose(
        """
        Request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
        Body: \(stringify(request.body))
        """
      )

      do {
        let response = try await next(request)
        logger.verbose(
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
