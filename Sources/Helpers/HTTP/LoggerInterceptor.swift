//
//  LoggerInterceptor.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation

package struct LoggerInterceptor: HTTPClientInterceptor {
  let logger: any SupabaseLogger

  package init(logger: any SupabaseLogger) {
    self.logger = logger
  }

  package func intercept(
    _ request: HTTPRequest,
    _ bodyData: Data?,
    next: @Sendable (HTTPRequest, Data?) async throws -> (Data, HTTPResponse)
  ) async throws -> (Data, HTTPResponse) {
    let id = UUID().uuidString
    return try await SupabaseLoggerTaskLocal.$additionalContext.withValue(merging: ["requestID": .string(id)]) {
      logger.verbose(
        """
        Request: \(request.method.rawValue) \(request.url?.absoluteString.removingPercentEncoding ?? "")
        Body: \(stringfy(bodyData))
        """
      )

      do {
        let (data, response) = try await next(request, bodyData)
        logger.verbose(
          """
          Response: Status code: \(response.status.code) Content-Length: \(
            response.headerFields[.contentLength] ?? "<none>"
          )
          Body: \(stringfy(data))
          """
        )
        return (data, response)
      } catch {
        logger.error("Response: Failure \(error)")
        throw error
      }
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
