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

import struct Foundation.URL

/// A type that performs HTTP operations.
///
/// Decouples an underlying HTTP library from generated client code.
///
/// ### Choose between a transport and a middleware
///
/// The ``ClientTransport`` and ``ClientMiddleware`` protocols look similar,
/// however each serves a different purpose.
///
/// A _transport_ abstracts over the underlying HTTP library that actually
/// performs the HTTP operation by using the network. A ``Client``
/// requires an exactly one client transport.
///
/// A _middleware_ intercepts the HTTP request and response, without being
/// responsible for performing the HTTP operation itself. That's why
/// middlewares take the extra `next` parameter, to delegate making the HTTP
/// call to the transport at the top of the middleware stack.
///
/// ### Use an existing client transport
///
/// Instantiate the transport using the parameters required by the specific
/// implementation. For example, using the client transport for the
/// `URLSession` HTTP client provided by the Foundation framework:
///
///     let transport = URLSessionTransport()
///
/// Instantiate the `Client` type. For example:
///
///     let client = Client(
///         serverURL: URL(string: "https://example.com")!,
///         transport: transport
///     )
///
/// ### Implement a custom client transport
///
/// If a client transport implementation for your preferred HTTP library doesn't
/// yet exist, or you need to simulate rare network conditions in your tests,
/// consider implementing a custom client transport.
///
/// For example, to implement a test client transport that allows you
/// to test both a healthy and unhealthy response from a `checkHealth`
/// operation, define a new struct that conforms to the `ClientTransport`
/// protocol:
///
///     struct TestTransport: ClientTransport {
///         var isHealthy: Bool = true
///         func send(
///             _ request: HTTPRequest,
///             body: HTTPBody?,
///             baseURL: URL,
///             operationID: String
///         ) async throws -> (HTTPResponse, HTTPBody?) {
///             (
///                 HTTPResponse(status: isHealthy ? .ok : .internalServerError),
///                 nil
///             )
///         }
///     }
///
/// Then in your test code, instantiate and provide the test transport to your
/// generated client instead:
///
///     var transport = TestTransport()
///     transport.isHealthy = true // for HTTP status code 200 (success)
///     let client = Client(
///         serverURL: URL(string: "https://example.com")!,
///         transport: transport
///     )
///     let response = try await client.checkHealth()
///
/// Implementing a test client transport is just one way to help test your
/// code that integrates with a generated client. Another is to implement
/// a type conforming to the generated protocol `APIProtocol`, and to implement
/// a custom ``ClientMiddleware``.
public protocol ClientTransport: Sendable {

  /// Sends the underlying HTTP request and returns the received
  /// HTTP response.
  /// - Parameters:
  ///   - request: An HTTP request.
  ///   - body: An HTTP request body.
  ///   - baseURL: A server base URL.
  ///   - operationID: The identifier of the OpenAPI operation.
  /// - Returns: An HTTP response and its body.
  /// - Throws: An error if sending the request and receiving the response fails.
  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
}

/// A type that intercepts HTTP requests and responses.
///
/// It allows you to read and modify the request before it is received by
/// the transport and the response after it is returned by the transport.
///
/// Appropriate for handling authentication, logging, metrics, tracing,
/// injecting custom headers such as "user-agent", and more.
///
/// ### Choose between a transport and a middleware
///
/// The ``ClientTransport`` and ``ClientMiddleware`` protocols look similar,
/// however each serves a different purpose.
///
/// A _transport_ abstracts over the underlying HTTP library that actually
/// performs the HTTP operation by using the network. A ``Client``
/// requires an exactly one client transport.
///
/// A _middleware_ intercepts the HTTP request and response, without being
/// responsible for performing the HTTP operation itself. That's why
/// middlewares take the extra `next` parameter, to delegate making the HTTP
/// call to the transport at the top of the middleware stack.
///
/// ### Use an existing client middleware
///
/// Instantiate the middleware using the parameters required by the specific
/// implementation. For example, using a hypothetical existing middleware
/// that logs every request and response:
///
///     let loggingMiddleware = LoggingMiddleware()
///
/// Similarly to the process of using an existing ``ClientTransport``, provide
/// the middleware to the initializer of the ``Client`` type:
///
///     let client = Client(
///         serverURL: URL(string: "https://example.com")!,
///         transport: transport,
///         middlewares: [
///             loggingMiddleware,
///         ]
///     )
///
/// Then make a call to one of the client methods:
///
///     let response = try await client.checkHealth()
///
/// As part of the invocation of `checkHealth`, the client first invokes
/// the middlewares in the order you provided them, and then passes the request
/// to the transport. When a response is received, the last middleware handles
/// it first, in the reverse order of the `middlewares` array.
///
/// ### Implement a custom client middleware
///
/// If a client middleware implementation with your desired behavior doesn't
/// yet exist, or you need to simulate rare network conditions your tests,
/// consider implementing a custom client middleware.
///
/// For example, to implement a middleware that injects the "Authorization"
/// header to every outgoing request, define a new struct that conforms to
/// the `ClientMiddleware` protocol:
///
///     /// Injects an authorization header to every request.
///     struct AuthenticationMiddleware: ClientMiddleware {
///
///         /// The token value.
///         var bearerToken: String
///
///         func intercept(
///             _ request: HTTPRequest,
///             body: HTTPBody?,
///             baseURL: URL,
///             operationID: String,
///             next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
///         ) async throws -> (HTTPResponse, HTTPBody?) {
///             var request = request
///             request.headerFields[.authorization] = "Bearer \(bearerToken)"
///             return try await next(request, body, baseURL)
///         }
///     }
///
/// An alternative use case for a middleware is to inject random failures
/// when calling a real server, to test your retry and error-handling logic.
///
/// Implementing a test client middleware is just one way to help test your
/// code that integrates with a generated client. Another is to implement
/// a type conforming to the generated protocol `APIProtocol`, and to implement
/// a custom ``ClientTransport``.
protocol ClientMiddleware: Sendable {

  /// Intercepts an outgoing HTTP request and an incoming HTTP response.
  /// - Parameters:
  ///   - request: An HTTP request.
  ///   - body: An HTTP request body.
  ///   - baseURL: A server base URL.
  ///   - operationID: The identifier of the OpenAPI operation.
  ///   - next: A closure that calls the next middleware, or the transport.
  /// - Returns: An HTTP response and its body.
  /// - Throws: An error if interception of the request and response fails.
  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    next: @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
}
