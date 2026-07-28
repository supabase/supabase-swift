//
//  HTTPError.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation

/// Errors surfaced by the runtime itself (transport/encoding/decoding), as
/// distinct from typed API errors decoded from a response body.
package enum HTTPError: Error, Sendable {
  case invalidURL(base: URL, path: String)
  case transport(any Error & Sendable)
  case decoding(any Error & Sendable)
  // case encoding(any Error)
  /// A request shape the transport can't carry out, e.g. a file-backed body
  /// passed to `stream(_:)`, which only sends buffered/in-memory bodies.
  case unsupportedRequestBody(String)
  /// A non-success status whose body did not decode to any modeled error.
  case unexpectedResponse(response: HTTPResponse, underlyingError: (any Error & Sendable)? = nil)
}

/// Marker protocol for generated, typed API errors decoded from a response
/// body for a known status code.
package protocol APIError: Error, Sendable, Decodable {}

extension HTTPResponse {
  /// Validates the status code, decoding a modeled error when the status
  /// matches one of the provided error types. A status with no matching
  /// entry surfaces as ``HTTPError/unexpectedResponse``.
  package func checkStatus(
    errorTypes: [Int: any APIError.Type]
  ) throws {
    guard !head.isSuccess else { return }

    guard let errorType = errorTypes[head.status] else {
      throw HTTPError.unexpectedResponse(response: self)
    }

    let decodedError: any APIError
    do {
      decodedError = try JSONCoding.decoder.decode(errorType, from: body)
    } catch {
      throw HTTPError.unexpectedResponse(response: self, underlyingError: error)
    }
    throw decodedError
  }
}
