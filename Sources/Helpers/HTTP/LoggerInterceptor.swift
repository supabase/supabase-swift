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

/// Logs the outcome of each request at `.debug`: the method, the URL without its query and
/// fragment, the status code or a failure summary, and the time it took.
///
/// It never logs a header value or a request or response body. The bodies pass through
/// untouched.
package struct LoggerInterceptor: ClientMiddleware {
  let logger: Logging.Logger

  package init(logger: Logging.Logger) {
    self.logger = logger.redactingSecrets()
  }

  package func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    guard logger.logLevel <= .debug else {
      return try await next(request, body)
    }

    var logger = logger
    logger[metadataKey: "requestID"] = "\(UUID().uuidString)"
    let requestLine = "\(request.method.rawValue) \(Self.loggable(request.url))"
    let clock = ContinuousClock()
    let start = clock.now

    func elapsed() -> Int { Int(start.duration(to: clock.now).timeInterval * 1000) }

    do {
      let (head, responseBody) = try await next(request, body)
      logger.debug("\(requestLine) -> \(head.status.code) in \(elapsed()) ms")
      return (head, responseBody)
    } catch {
      logger.debug(
        "\(requestLine) failed in \(elapsed()) ms: \(LogRedaction.code(of: error))")
      throw error
    }
  }

  /// The URL without its query and fragment, which can hold a signed token or a filter value.
  private static func loggable(_ url: URL?) -> String {
    guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return ""
    }
    components.query = nil
    components.fragment = nil
    return components.string?.removingPercentEncoding ?? ""
  }
}
