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
    let id = UUID().uuidString
    var logger = logger
    logger[metadataKey: "requestID"] = "\(id)"

    let traces = logger.logLevel <= .trace
    let (requestBody, requestBodyText) = traces ? try await Self.loggable(body) : (body, "")
    logger.trace(
      """
      Request: \(request.method.rawValue) \(Self.loggable(request.url))
      Body: \(requestBodyText)
      """
    )

    do {
      let (head, responseBody) = try await next(request, requestBody)
      let (loggedBody, responseBodyText) =
        traces ? try await Self.loggable(responseBody) : (responseBody, "")
      logger.trace(
        """
        Response: Status code: \(head.status.code) Content-Length: \(head.headerFields[.contentLength] ?? "-")
        Body: \(responseBodyText)
        """
      )
      return (head, loggedBody)
    } catch {
      logger.error("Response: Failure (\(LogRedaction.summary(of: error)))")
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

  /// Buffers small known-length bodies for logging and re-wraps them; passes everything else
  /// through unconsumed.
  ///
  /// The declared length only decides *whether* to buffer. Collecting uses a much larger ceiling,
  /// because a body can deliver more bytes than it claims — with transparent gzip,
  /// `Content-Length` is the compressed size while the decoded bytes come out. Capping at the
  /// claim would throw ``HTTPBodyTooLargeError`` out of a logging middleware and fail the request,
  /// which is unrecoverable once the body has been consumed.
  private static func loggable(_ body: HTTPBody?) async throws -> (HTTPBody?, String) {
    guard let body else { return (nil, "<none>") }
    guard case .known(let count) = body.length, count <= maxLoggedBodyBytes else {
      return (body, "<streamed>")
    }
    let data = try await Data(collecting: body, upTo: Int(maxLoggedBodyBytes) * 16)
    let rewrapped = HTTPBody(data)
    return (body.onUploadProgress.map(rewrapped.reportingProgress) ?? rewrapped, stringify(data))
  }
}

func stringify(_ data: Data?) -> String {
  guard let data else {
    return "<none>"
  }

  do {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    let prettyData = try JSONSerialization.data(
      withJSONObject: redactingSecrets(in: object),
      options: [.prettyPrinted, .sortedKeys]
    )
    return String(data: prettyData, encoding: .utf8) ?? "<failed>"
  } catch {
    return String(data: data, encoding: .utf8) ?? "<failed>"
  }
}

private func redactingSecrets(in object: Any) -> Any {
  if let dictionary = object as? [String: Any] {
    return dictionary.reduce(into: [String: Any]()) { result, entry in
      result[entry.key] =
        LogRedaction.isSensitive(jsonKey: entry.key)
        ? LogRedaction.placeholder : redactingSecrets(in: entry.value)
    }
  }
  if let array = object as? [Any] {
    return array.map(redactingSecrets(in:))
  }
  return object
}
