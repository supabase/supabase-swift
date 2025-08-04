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

import protocol Foundation.LocalizedError

#if canImport(Darwin)
  import struct Foundation.URL
#else
  @preconcurrency import struct Foundation.URL
#endif

/// An error thrown by a client performing an OpenAPI operation.
///
/// Use a `ClientError` to inspect details about the request and response
/// that resulted in an error.
///
/// You don't create or throw instances of `ClientError` yourself; they are
/// created and thrown on your behalf by the runtime library when a client
/// operation fails.
struct ClientError: Error {
  /// The HTTP request created during the operation.
  ///
  /// Will be nil if the error resulted before the request was generated,
  /// for example if generating the request from the Input failed.
  var request: HTTPTypes.HTTPRequest?

  /// The HTTP request body created during the operation.
  ///
  /// Will be nil if the error resulted before the request was generated,
  /// for example if generating the request from the Input failed.
  var requestBody: HTTPBody?

  /// The base URL for HTTP requests.
  ///
  /// Will be nil if the error resulted before the request was generated,
  /// for example if generating the request from the Input failed.
  var baseURL: URL?

  /// The HTTP response received during the operation.
  ///
  /// Will be nil if the error resulted before the response was received.
  var response: HTTPTypes.HTTPResponse?

  /// The HTTP response body received during the operation.
  ///
  /// Will be nil if the error resulted before the response was received.
  var responseBody: HTTPBody?

  /// A user-facing description of what caused the underlying error
  /// to be thrown.
  var causeDescription: String

  /// The underlying error that caused the operation to fail.
  var underlyingError: any Error

  /// Creates a new error.
  /// - Parameters:
  ///   - request: The HTTP request created during the operation.
  ///   - requestBody: The HTTP request body created during the operation.
  ///   - baseURL: The base URL for HTTP requests.
  ///   - response: The HTTP response received during the operation.
  ///   - responseBody: The HTTP response body received during the operation.
  ///   - causeDescription: A user-facing description of what caused
  ///     the underlying error to be thrown.
  ///   - underlyingError: The underlying error that caused the operation
  ///     to fail.
  init(
    request: HTTPTypes.HTTPRequest? = nil,
    requestBody: HTTPBody? = nil,
    baseURL: URL? = nil,
    response: HTTPTypes.HTTPResponse? = nil,
    responseBody: HTTPBody? = nil,
    causeDescription: String,
    underlyingError: any Error
  ) {
    self.request = request
    self.requestBody = requestBody
    self.baseURL = baseURL
    self.response = response
    self.responseBody = responseBody
    self.causeDescription = causeDescription
    self.underlyingError = underlyingError
  }

  // MARK: Private

  fileprivate var underlyingErrorDescription: String {
    guard let prettyError = underlyingError as? (any PrettyStringConvertible) else {
      return "\(underlyingError)"
    }
    return prettyError.prettyDescription
  }
}

extension ClientError: CustomStringConvertible {
  /// A human-readable description of the client error.
  ///
  /// This computed property returns a string that includes information about the client error.
  ///
  /// - Returns: A string describing the client error and its associated details.
  var description: String {
    "Client error - cause description: '\(causeDescription)', underlying error: \(underlyingErrorDescription), request: \(request?.prettyDescription ?? "<nil>"), requestBody: \(requestBody?.prettyDescription ?? "<nil>"), baseURL: \(baseURL?.absoluteString ?? "<nil>"), response: \(response?.prettyDescription ?? "<nil>"), responseBody: \(responseBody?.prettyDescription ?? "<nil>")"
  }
}

extension ClientError: LocalizedError {
  /// A localized description of the client error.
  ///
  /// This computed property provides a localized human-readable description of the client error, which is suitable for displaying to users.
  ///
  /// - Returns: A localized string describing the client error.
  var errorDescription: String? {
    "Client encountered an error, caused by \"\(causeDescription)\", underlying error: \(underlyingError.localizedDescription)."
  }
}
