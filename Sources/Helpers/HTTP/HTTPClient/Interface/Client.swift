//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import HTTPTypes

#if canImport(Darwin)
  import struct Foundation.URL
#else
  @preconcurrency import struct Foundation.URL
#endif

/// A client that can send HTTP requests and receive HTTP responses.
struct Client: Sendable {

  /// The URL of the server, used as the base URL for requests made by the
  /// client.
  let serverURL: URL

  /// A type capable of sending HTTP requests and receiving HTTP responses.
  var transport: any ClientTransport

  /// The middlewares to be invoked before the transport.
  var middlewares: [any ClientMiddleware]

  /// Creates a new client.
  init(
    serverURL: URL,
    transport: any ClientTransport,
    middlewares: [any ClientMiddleware] = []
  ) {
    self.serverURL = serverURL
    self.transport = transport
    self.middlewares = middlewares
  }

  /// Sends the HTTP request and returns the HTTP response.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - body: The HTTP request body to send.
  /// - Returns: The HTTP response and its body.
  /// - Throws: An error if any part of the HTTP operation process fails.
  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody? = nil
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    @Sendable func wrappingErrors<R>(
      work: () async throws -> R,
      mapError: (any Error) -> ClientError
    ) async throws -> R {
      do {
        return try await work()
      } catch let error as ClientError {
        throw error
      } catch {
        throw mapError(error)
      }
    }
    let baseURL = serverURL
    @Sendable func makeError(
      request: HTTPTypes.HTTPRequest? = nil,
      requestBody: HTTPBody? = nil,
      baseURL: URL? = nil,
      response: HTTPTypes.HTTPResponse? = nil,
      responseBody: HTTPBody? = nil,
      error: any Error
    ) -> ClientError {
      if var error = error as? ClientError {
        error.request = error.request ?? request
        error.requestBody = error.requestBody ?? requestBody
        error.baseURL = error.baseURL ?? baseURL
        error.response = error.response ?? response
        error.responseBody = error.responseBody ?? responseBody
        return error
      }
      let causeDescription: String
      let underlyingError: any Error
      if let runtimeError = error as? RuntimeError {
        causeDescription = runtimeError.prettyDescription
        underlyingError = runtimeError.underlyingError ?? error
      } else {
        causeDescription = "Unknown"
        underlyingError = error
      }
      return ClientError(
        request: request,
        requestBody: requestBody,
        baseURL: baseURL,
        response: response,
        responseBody: responseBody,
        causeDescription: causeDescription,
        underlyingError: underlyingError
      )
    }
    var next: @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) = {
      (_request, _body, _url) in
      try await wrappingErrors {
        try await transport.send(
          _request,
          body: _body,
          baseURL: _url
        )
      } mapError: { error in
        makeError(
          request: request,
          requestBody: body,
          baseURL: baseURL,
          error: RuntimeError.transportFailed(error)
        )
      }
    }
    for middleware in middlewares.reversed() {
      let tmp = next
      next = { (_request, _body, _url) in
        try await wrappingErrors {
          try await middleware.intercept(
            _request,
            body: _body,
            baseURL: _url,
            next: tmp
          )
        } mapError: { error in
          makeError(
            request: request,
            requestBody: body,
            baseURL: baseURL,
            error: RuntimeError.middlewareFailed(
              middlewareType: type(of: middleware),
              error
            )
          )
        }
      }
    }
    return try await next(request, body, baseURL)
  }
}
