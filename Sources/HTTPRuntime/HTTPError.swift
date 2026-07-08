//
//  HTTPError.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
public import Foundation

/// Errors surfaced by the runtime itself (transport/encoding/decoding), as
/// distinct from typed API errors decoded from a response body.
public enum HTTPError: Error, Sendable {
  case invalidURL(base: URL, path: String)
  case transport(any Error)
  case decoding(any Error)
  case encoding(any Error)
  /// A non-success status whose body did not decode to any modeled error.
  case unexpectedStatus(status: Int, body: Data)
}

/// Marker protocol for generated, typed API errors decoded from a response
/// body for a known status code.
public protocol APIError: Error, Sendable, Decodable {}

extension HTTPResponse {
  /// Validates the status code, decoding a modeled error when the status
  /// matches one of the provided error types. Generated code passes the
  /// `status -> ErrorType` table declared by the operation's Smithy/TypeSpec
  /// error bindings.
  public func checkStatus(errorTypes: [Int: any APIError.Type]) throws {
    guard !isSuccess else { return }
    if let errorType = errorTypes[status] {
      do {
        let decoded = try JSONCoding.decoder.decode(errorType, from: body)
        throw decoded
      } catch let error as any APIError {
        throw error
      } catch {
        throw HTTPError.decoding(error)
      }
    }
    throw HTTPError.unexpectedStatus(status: status, body: body)
  }
}
