//
//  PostgrestRequest.swift
//  PostgREST
//
//  Created by Guilherme Souza on 02/10/26.
//

import Foundation
import HTTPTypes
import Helpers
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The request a ``PostgrestQuery``, ``PostgrestMutation`` or ``PostgrestRawQuery`` sends, held as
/// a plain value.
///
/// Every method on those types returns a copy with a changed request, so chaining off the same
/// value twice gives two independent requests.
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
///
/// Its members are not public yet. Reading a request back without sending it is planned, but the
/// shape is not settled.
public struct PostgrestRequest: Sendable {
  var method: HTTPTypes.HTTPRequest.Method
  var relation: String
  var query: [URLQueryItem] = []
  var headerFields = HTTPFields()
  var body: Data?

  init(method: HTTPTypes.HTTPRequest.Method = .get, relation: String) {
    self.method = method
    self.relation = relation
  }

  /// Adds or replaces one preference in the `Prefer` header and keeps the others.
  mutating func setPreference(_ value: String) {
    headerFields.appendOrUpdate(.prefer, value: value)
  }

  /// Sends the request and decodes a successful response.
  ///
  /// - Parameters:
  ///   - client: Supplies the base URL, headers, schema, access token and transport.
  ///   - decode: Turns a 2xx body into the value.
  func execute<T>(
    on client: PostgrestClient,
    decode: (Data, JSONDecoder) throws -> T
  ) async throws -> PostgrestResponse<T> {
    let configuration = client.configuration
    var request = httpRequest(for: configuration)

    if let accessToken = configuration.accessToken, request.headerFields[.authorization] == nil,
      let token = try await accessToken()
    {
      request.headerFields[.authorization] = "Bearer \(token)"
    }

    let http = HTTPClient(
      configuration: configuration.http,
      retrying: RetryRequestInterceptor(
        policy: configuration.retryEnabled
          ? PostgrestClient.Configuration.retryPolicy : .disabled,
        clock: client.clock),
      appending: [LoggerInterceptor(logger: configuration.logger)])

    let response: HTTPTypes.HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body)
    } catch let urlError as URLError {
      throw PostgrestError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    if 200..<300 ~= response.status.code {
      do {
        return PostgrestResponse(
          data: data, response: response, value: try decode(data, configuration.decoder))
      } catch let error as PostgrestError {
        throw error
      } catch {
        configuration.logger.error("Failed to decode type '\(T.self)' with error: \(error)")
        throw PostgrestError(
          kind: .decoding,
          message: "Failed to decode the PostgREST response as \(T.self).",
          underlyingError: error
        )
      }
    }

    // A fixed decoder: the configured one carries key and date strategies for row types, and
    // `ServerError` matches PostgREST's keys exactly.
    guard let serverError = try? JSONDecoder().decode(PostgrestError.ServerError.self, from: data)
    else {
      throw PostgrestError(
        kind: .server,
        message: "Unexpected response with status code \(response.status.code).",
        response: HTTPErrorResponse(response, body: data)
      )
    }
    throw PostgrestError(
      kind: .server,
      message: serverError.message,
      serverError: serverError,
      response: HTTPErrorResponse(response, body: data)
    )
  }

  func httpRequest(for configuration: PostgrestClient.Configuration) -> HTTPTypes.HTTPRequest {
    var fields = HTTPFields(configuration.headers)
    for field in headerFields {
      fields[field.name] = field.value
    }
    if fields[.accept] == nil {
      fields[.accept] = "application/json"
    }
    fields[.contentType] = "application/json"
    if let schema = configuration.schema {
      fields[method == .get || method == .head ? .acceptProfile : .contentProfile] = schema
    }
    return HTTPTypes.HTTPRequest(
      method: method,
      url: configuration.url.appendingPathComponent(relation).appendingQueryItems(query),
      headerFields: fields
    )
  }
}
