//
//  LoggerInterceptor.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation
package import HTTPTypes
import HTTPTypesFoundation
package import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct LoggerInterceptor: ClientMiddleware {
  let logger: Logging.Logger

  /// Bodies at or under this size are buffered so they can be logged. Larger or
  /// unknown-length bodies pass through untouched as `<streamed>`.
  static let maxLoggedBodyBytes: Int64 = 64 * 1024

  package init(logger: Logging.Logger) {
    self.logger = logger
  }

  package func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    let id = UUID().uuidString
    var logger = logger
    logger[metadataKey: "requestID"] = "\(id)"

    let (requestBody, requestBodyText) = try await Self.loggable(body)
    logger.trace(
      """
      Request: \(request.method.rawValue) \(request.url?.absoluteString.removingPercentEncoding ?? "")
      Body: \(requestBodyText)
      """
    )

    do {
      let (head, responseBody) = try await next(request, requestBody)
      let (loggedBody, responseBodyText) = try await Self.loggable(responseBody)
      logger.trace(
        """
        Response: Status code: \(head.status.code) Content-Length: \(head.headerFields[.contentLength] ?? "-")
        Body: \(responseBodyText)
        """
      )
      return (head, loggedBody)
    } catch {
      logger.error("Response: Failure \(error)")
      throw error
    }
  }

  /// Buffers small known-length bodies for logging and re-wraps them; passes everything else
  /// through unconsumed.
  private static func loggable(_ body: HTTPBody?) async throws -> (HTTPBody?, String) {
    guard let body else { return (nil, "<none>") }
    guard case .known(let count) = body.length, count <= maxLoggedBodyBytes else {
      return (body, "<streamed>")
    }
    let data = try await Data(collecting: body, upTo: Int(count))
    return (HTTPBody(data), stringify(data))
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
