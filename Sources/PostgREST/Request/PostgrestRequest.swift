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
  var headerFields: HTTPFields
  var body: Data?

  /// Overrides ``PostgrestClient/Configuration/retryEnabled`` for this request when set.
  var retryEnabled: Bool?

  /// The idle timeout for this request, or `nil` for the client's.
  var timeout: Duration?

  /// Asks PostgREST to drop `null` fields from JSON responses. Applied when the request is built,
  /// because `single()` may still change the media type it has to be added to.
  var stripsNulls = false

  /// Turns the "no rows" variant of PGRST116 into the value decoded from `null`, for
  /// `maybeSingle()`. The "multiple rows" variant still throws.
  var nullOnNoRows = false

  init(
    method: HTTPTypes.HTTPRequest.Method = .get,
    relation: String,
    headerFields: HTTPFields = HTTPFields()
  ) {
    self.method = method
    self.relation = relation
    self.headerFields = headerFields
  }

  /// Adds or replaces one preference in the `Prefer` header and keeps the others.
  mutating func setPreference(_ value: String) {
    headerFields.appendOrUpdate(.prefer, value: value)
  }

  /// Sends the request and decodes a successful response.
  ///
  /// - Parameters:
  ///   - client: Supplies the base URL, headers, schema, access token and transport.
  ///   - decode: Turns a 2xx body into the value. It carries its own decoder, so the core never
  ///     reads ``PostgrestClient/Configuration/decoder``.
  func execute<T>(
    on client: PostgrestClient,
    decode: (Data) throws -> T
  ) async throws -> PostgrestResponse<T> {
    let configuration = client.configuration
    var request = httpRequest(for: configuration)

    if let accessToken = configuration.accessToken, request.headerFields[.authorization] == nil,
      let token = try await accessToken()
    {
      request.headerFields[.authorization] = "Bearer \(token)"
    }

    let retries = retryEnabled ?? configuration.retryEnabled
    let http = HTTPClient(
      configuration: configuration.http,
      retrying: RetryRequestInterceptor(
        policy: retries ? PostgrestClient.Configuration.retryPolicy : .disabled,
        clock: client.clock),
      appending: [LoggerInterceptor(logger: configuration.logger)])

    let response: HTTPTypes.HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body, timeout: timeout)
    } catch let urlError as URLError {
      throw PostgrestError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    if 200..<300 ~= response.status.code {
      do {
        return PostgrestResponse(data: data, response: response, value: try decode(data))
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
    if nullOnNoRows, serverError.code == "PGRST116", serverError.matchedZeroRows {
      return PostgrestResponse(
        data: data, response: response, value: try decode(Data("null".utf8)))
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
    if stripsNulls {
      switch fields[.accept] {
      case "application/vnd.pgrst.object+json":
        fields[.accept] = "application/vnd.pgrst.object+json;nulls=stripped"
      case "application/json":
        fields[.accept] = "application/vnd.pgrst.array+json;nulls=stripped"
      default:
        break
      }
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

extension PostgrestClient {
  /// Starts a request against a relation or `rpc/<function>` path, carrying this client's
  /// headers. Every PostgREST request, typed or untyped, starts here.
  func makeRequest(
    _ relation: String,
    method: HTTPTypes.HTTPRequest.Method = .get
  ) -> PostgrestRequest {
    PostgrestRequest(
      method: method, relation: relation, headerFields: HTTPFields(configuration.headers))
  }
}

extension HTTPField.Name {
  static let acceptProfile = Self("Accept-Profile")!
  static let contentProfile = Self("Content-Profile")!
}
