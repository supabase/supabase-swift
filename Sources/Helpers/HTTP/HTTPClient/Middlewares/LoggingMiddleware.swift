import Logging

#if canImport(Darwin)
  import struct Foundation.URL
  import struct Foundation.UUID
#else
  @preconcurrency import struct Foundation.URL
  @preconcurrency import struct Foundation.UUID
#endif

struct LoggingMiddleware: ClientMiddleware {
  let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    next: (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var logger = logger
    logger[metadataKey: "request-id"] = .string(UUID().uuidString)
    
    logger.trace("⬆️ \(request.prettyDescription)")
    let (response, body) = try await next(request, body, baseURL)
    logger.trace("⬇️ \(response.prettyDescription)")
    return (response, body)
  }
}
