//
//  HTTPRuntimeError.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation
package import HTTPTypes

/// Errors surfaced by the runtime itself (transport/encoding/decoding), as
/// distinct from typed API errors decoded from a response body.
package enum HTTPRuntimeError: Error, Sendable {
  case invalidURL(base: URL, path: String)
  case transport(any Error & Sendable)
  case decoding(any Error & Sendable)
  /// A request shape the transport can't carry out, e.g. a file-backed body
  /// passed to `stream(_:)`, which only sends buffered/in-memory bodies.
  case unsupportedRequestBody(String)
  /// A non-success status whose body did not decode to any modeled error.
  /// Carries the buffered response, not the bare head — an unexpected status
  /// is exactly when the caller wants the body.
  case unexpectedResponse(
    response: HTTPBufferedResponse, underlyingError: (any Error & Sendable)? = nil)
}

/// Marker protocol for generated, typed API errors decoded from a response
/// body for a known status code.
package protocol APIError: Error, Sendable, Decodable {}

extension HTTPBufferedResponse {
  /// Validates the status code, decoding a modeled error when the status
  /// matches one of the provided error types.
  package func checkStatus(
    errorTypes: [HTTPResponse.Status: any APIError.Type],
    catchAll defaultError: any APIError.Type
  ) throws {
    guard head.status.kind != .successful else { return }

    let errorType = errorTypes[head.status] ?? defaultError

    let decodedError: any APIError
    do {
      decodedError = try JSONCoding.decoder.decode(errorType, from: body)
    } catch {
      throw HTTPRuntimeError.unexpectedResponse(response: self, underlyingError: error)
    }
    throw decodedError
  }
}
