import Logging
import OpenAPIRuntime

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
    operationID: String,
    next: (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var logger = logger
    logger[metadataKey: "request-id"] = .string(UUID().uuidString)

    logger.trace("⬆️ \(request.prettyDescription)")
    let (response, body) = try await next(request, body, baseURL)
    logger.trace("⬇️ \(response.prettyDescription)")
    return (response, body)
  }
}

extension HTTPFields {
  fileprivate var prettyDescription: String {
    sorted(by: {
      $0.name.canonicalName.localizedCompare($1.name.canonicalName) == .orderedAscending
    })
    .map { "\($0.name.canonicalName): \($0.value)" }.joined(separator: "; ")
  }
}

extension HTTPTypes.HTTPRequest {
  fileprivate var prettyDescription: String {
    "\(method.rawValue) \(path ?? "<nil>") [\(headerFields.prettyDescription)]"
  }
}

extension HTTPTypes.HTTPResponse {
  fileprivate var prettyDescription: String { "\(status.code) [\(headerFields.prettyDescription)]" }
}

extension HTTPBody { fileprivate var prettyDescription: String { String(describing: self) } }
