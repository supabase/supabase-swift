import HTTPTypes

import struct Foundation.Data
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
import protocol Foundation.LocalizedError

/// Error thrown by generated code.
internal enum RuntimeError: Error, CustomStringConvertible, LocalizedError, PrettyStringConvertible
{

  // Transport/Handler
  case transportFailed(any Error)
  case middlewareFailed(middlewareType: Any.Type, any Error)

  /// A wrapped root cause error, if one was thrown by other code.
  var underlyingError: (any Error)? {
    switch self {
    case .transportFailed(let error), .middlewareFailed(_, let error):
      return error
    }
  }

  // MARK: CustomStringConvertible

  var description: String { prettyDescription }

  var prettyDescription: String {
    switch self {
    case .transportFailed: return "Transport threw an error."
    case .middlewareFailed(middlewareType: let type, _):
      return "Middleware of type '\(type)' threw an error."
    }
  }

  // MARK: - LocalizedError

  var errorDescription: String? { description }
}

/// HTTP Response status definition for ``RuntimeError``.
extension RuntimeError: HTTPResponseConvertible {
  /// HTTP Status code corresponding to each error case
  var httpStatus: HTTPTypes.HTTPResponse.Status {
    switch self {
    case .middlewareFailed, .transportFailed:
      .internalServerError
    }
  }
}

/// A value that can be converted to an HTTP response and body.
///
/// Conform your error type to this protocol to convert it to an `HTTPResponse` and ``HTTPBody``.
///
/// Used by ``ErrorHandlingMiddleware``.
protocol HTTPResponseConvertible {

  /// An HTTP status to return in the response.
  var httpStatus: HTTPTypes.HTTPResponse.Status { get }

  /// The HTTP header fields of the response.
  /// This is optional as default values are provided in the extension.
  var httpHeaderFields: HTTPTypes.HTTPFields { get }

  /// The body of the HTTP response.
  var httpBody: HTTPBody? { get }
}

extension HTTPResponseConvertible {

  // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
  var httpHeaderFields: HTTPTypes.HTTPFields { [:] }

  // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
  var httpBody: HTTPBody? { nil }
}
