//
//  CatalogTransport.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import Foundation
import HTTPTypes

@_spi(Experimental) import Storage

extension IcebergCatalog {
  /// Sends `method` to `path` under this catalog's bucket and decodes the 2xx body as `Response`.
  func send<Response: Decodable>(
    _ method: HTTPRequest.Method,
    path: [String],
    query: [URLQueryItem] = [],
    body: (any Encodable)? = nil
  ) async throws -> Response {
    let data = try await sendRequest(method, path: path, query: query, body: body)
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw StorageError(
        kind: .decoding,
        message: "Failed to decode the Iceberg catalog response as \(Response.self).",
        underlyingError: error)
    }
  }

  /// Sends `method` to `path` under this catalog's bucket and ignores the 2xx body.
  func sendIgnoringBody(
    _ method: HTTPRequest.Method,
    path: [String],
    query: [URLQueryItem] = [],
    body: (any Encodable)? = nil
  ) async throws {
    _ = try await sendRequest(method, path: path, query: query, body: body)
  }

  /// Sends `HEAD` to `path` under this catalog's bucket: `true` on a 2xx, `false` on a 404.
  func exists(path: [String]) async throws -> Bool {
    do {
      try await sendIgnoringBody(.head, path: path)
      return true
    } catch let error as StorageError where error.response?.status == .notFound {
      return false
    }
  }

  private func sendRequest(
    _ method: HTTPRequest.Method,
    path: [String],
    query: [URLQueryItem],
    body: (any Encodable)?
  ) async throws -> Data {
    try await analytics.sendCatalogRequest(
      method, path: [bucket] + path, query: query, body: body.map(Self.encode))
  }

  private static func encode(_ body: any Encodable) throws -> Data {
    do {
      return try JSONEncoder().encode(body)
    } catch {
      throw StorageError(
        kind: .invalidRequest,
        message: "The Iceberg catalog request body cannot be encoded as JSON.",
        underlyingError: error)
    }
  }
}
