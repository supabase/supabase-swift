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
    return try await SupabaseLoggerTaskLocal.$additionalContext.withValue(merging: [
      "requestID": .string(id)
    ]) {
      let urlRequest = request.urlRequest

      logger.verbose(
        """
        Request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
        Body: \(stringfy(request.body))
        """
      )

      do {
        let response = try await next(request)
        logger.verbose(
          """
          Response: Status code: \(response.statusCode) Content-Length: \(
            response.underlyingResponse.expectedContentLength
          )
          Body: \(stringfy(response.data))
          """
        )
        return response
      } catch {
        logger.error("Response: Failure \(error)")
        throw error
      }
    }
  }

  package func interceptRequest(_ request: HTTPRequest) async throws -> HTTPRequest {
    let urlRequest = request.urlRequest
    logger.verbose(
      """
      Streaming Request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
      Body: \(stringfy(request.body))
      """
    )
    return request
  }

  package func onStreamingResponseComplete(_ request: HTTPRequest, error: (any Error)?) async {
    let urlRequest = request.urlRequest
    if let error {
      logger.error(
        """
        Streaming Response: Failure for \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
        Error: \(error)
        """
      )
    } else {
      logger.verbose(
        """
        Streaming Response: Completed for \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString.removingPercentEncoding ?? "")
        """
      )
    }
  }
}

func stringfy(_ data: Data?) -> String {
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
