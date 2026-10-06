//
//  FunctionsAPI.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

import Foundation
import HTTPTypes
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The one place a request is built, sent and its head classified.
///
/// Both `invoke` and `stream` go through ``exchange(name:body:options:configuration:http:)``;
/// nothing else inspects a response head or relabels a transport failure.
enum FunctionsAPI {
  /// The most bytes of a non-2xx body kept on ``FunctionsError/response``. The rest is dropped
  /// so an unbounded error response cannot hold the call open or exhaust memory (SDK-1840).
  static let maxErrorBodyBytes = 1 << 20

  /// Builds the request head and body for one invocation. Pure: no token lookup, no I/O.
  ///
  /// Headers merge lowest to highest: `X-Client-Info`, then `configuration.headers`, then the
  /// body's `Content-Type`, then `options.headers`. The body's type sits above the client
  /// headers so a client-wide `Content-Type` cannot relabel a JSON body; a per-call one still
  /// wins. A region, per call or client-wide, goes out as both the `x-region` header and the
  /// `forceFunctionRegion` query item, which is what the gateway reads.
  static func makeRequest(
    name: String,
    body: FunctionBody?,
    options: FunctionInvokeOptions,
    configuration: FunctionsClient.Configuration
  ) -> (HTTPRequest, HTTPBody?) {
    var headers: HTTPFields = [.xClientInfo: "functions-swift/\(version)"]
    headers.merge(with: configuration.headers)
    if let body { headers[.contentType] = body.contentType }
    headers.merge(with: options.headers)

    var query = options.query
    if let region = options.region ?? configuration.region {
      headers[.xRegion] = region.rawValue
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region.rawValue))
    }

    let request = HTTPRequest(
      method: options.method,
      url: configuration.url.appendingPathComponent(name),
      query: query,
      headerFields: headers
    )
    return (request, body?.httpBody)
  }

  /// Builds and sends one invocation, returning the head and the unread body once the head
  /// passes ``throwIfFailed(_:body:)``. The bearer token is `AccessTokenMiddleware`'s job.
  static func exchange(
    name: String,
    body: FunctionBody?,
    options: FunctionInvokeOptions,
    configuration: FunctionsClient.Configuration,
    http: HTTPClient
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let (request, requestBody) = makeRequest(
      name: name, body: body, options: options, configuration: configuration)
    do {
      let (head, responseBody) = try await http.stream(
        request, body: requestBody, timeout: options.timeout)
      try await throwIfFailed(head, body: responseBody)
      return (head, responseBody)
    } catch {
      throw mapTransportError(error)
    }
  }

  /// Throws ``FunctionsError`` with kind `.relay` or `.server` when `head` is a failure, carrying
  /// the first ``maxErrorBodyBytes`` of `body` and the platform's `sb-error-code`.
  ///
  /// The relay check runs first: relay failures are non-2xx too.
  static func throwIfFailed(_ head: HTTPResponse, body: HTTPBody?) async throws {
    let kind: FunctionsError.Kind
    let message: String
    if head.headerFields[.xRelayError] == "true" {
      kind = .relay
      message = "Relay Error invoking the Edge Function"
    } else if head.status.kind != .successful {
      kind = .server
      message = "Edge Function returned a non-2xx status code: \(head.status.code)"
    } else {
      return
    }

    var data = Data()
    if let body {
      for try await chunk in body {
        data.append(contentsOf: chunk.prefix(maxErrorBodyBytes - data.count))
        if data.count >= maxErrorBodyBytes { break }
      }
    }
    throw FunctionsError(
      kind: kind,
      message: message,
      code: head.headerFields[.sbErrorCode].map(FunctionsError.Code.init(rawValue:)),
      response: HTTPErrorResponse(head, body: data)
    )
  }

  /// Relabels the network layer's own failures as `.transport`. `CancellationError`, a
  /// `FunctionsError` and anything thrown by user code that runs inside the exchange (a custom
  /// `ClientTransport` or middleware, the `accessToken` closure) propagate as themselves, unless
  /// it is a `URLError`: the chain cannot tell one of those from the transport's own.
  static func mapTransportError(_ error: any Error) -> any Error {
    guard let urlError = error as? URLError else { return error }
    // `URLSession` reports a cancelled `Task` as `URLError(.cancelled)`. A `.cancelled` with no
    // task cancellation behind it (a middleware cancelled the request) stays a transport error.
    if urlError.code == .cancelled, Task.isCancelled { return CancellationError() }
    return FunctionsError(
      kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
  }
}
