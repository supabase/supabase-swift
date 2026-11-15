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

/// The request every PostgREST call sends, held as a plain value: the typed ``_PostgrestQuery``,
/// ``_PostgrestMutation`` and ``_PostgrestRawQuery``, and the untyped ``PostgrestRequestBuilder``.
///
/// Every method on those types returns a copy with a changed request, so chaining off the same
/// value twice gives two independent requests.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
///
/// Its members are not public yet. Reading a request back without sending it is planned, but the
/// shape is not settled.
public struct _PostgrestRequest: Sendable {
  var method: HTTPTypes.HTTPRequest.Method
  var relation: String
  var query: [URLQueryItem] = []

  /// Query items sent ahead of ``query`` that a later item with the same name never replaces: the
  /// arguments of a GET or HEAD `rpc` call.
  var leadingQuery: [URLQueryItem] = []

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

  /// Why a filter on this request has no wire form, set by the first such filter. A filter method
  /// cannot throw, so the failure waits here and `execute()` throws it before anything is sent.
  var invalidFilterReason: String?

  /// The SDK features used to build this request, added to its `X-Client-Info` header.
  var clientInfoFeatures: Set<ClientInfoFeature> = []

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
  /// - Returns: A ``PostgrestResponse`` whose `value` is the result of `decode`.
  /// - Throws: ``PostgrestError`` with kind `.invalidRequest` if the request cannot be sent,
  ///   `.server` if PostgREST returns a non-2xx status, `.transport` if the request never
  ///   completes, `.accessToken` if the access token provider fails, or `.decoding` if `decode`
  ///   throws an error that is not a ``PostgrestError``. `CancellationError` if the task is
  ///   cancelled.
  func execute<T>(
    on client: PostgrestClient,
    decode: (Data) throws -> T
  ) async throws -> PostgrestResponse<T> {
    if let invalidFilterReason {
      throw PostgrestError(kind: .invalidRequest, message: invalidFilterReason)
    }

    if stripsNulls, headerFields[.accept] == "text/csv" {
      throw PostgrestError(
        kind: .invalidRequest, message: "`.csv()` cannot be combined with `.stripNulls()`")
    }

    let configuration = client.configuration
    let request = httpRequest(for: configuration)

    let retries = retryEnabled ?? configuration.retryEnabled
    let http = HTTPClient(
      configuration: configuration.http,
      retrying: RetryRequestInterceptor(
        policy: retries ? PostgrestClient.Configuration.retryPolicy : .disabled,
        clock: client.configuration.clock),
      appending: [LoggerInterceptor(logger: configuration.logger)])

    let response: HTTPTypes.HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(request, body: body, timeout: timeout)
    } catch let urlError as URLError {
      throw PostgrestError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    } catch let failure as AccessTokenFailure {
      throw PostgrestError(
        kind: .accessToken,
        message: AccessTokenFailure.message,
        underlyingError: failure.underlyingError
      )
    }

    func decoded(_ response: HTTPTypes.HTTPResponse, body: Data) throws -> PostgrestResponse<T> {
      do {
        return PostgrestResponse(response, body: body, value: try decode(body))
      } catch let error as PostgrestError {
        throw error
      } catch {
        configuration.logger.error(
          "Failed to decode type '\(T.self)' with error: \(LogRedaction.summary(of: error))")
        throw PostgrestError(
          kind: .decoding,
          message: "Failed to decode the PostgREST response as \(T.self).",
          underlyingError: error
        )
      }
    }

    if 200..<300 ~= response.status.code {
      return try decoded(response, body: data)
    }

    let error = PostgrestError.server(response, body: data)
    if nullOnNoRows, error.code == "PGRST116", error.serverError?.matchedZeroRows == true {
      // No row is a success for `maybeSingle()`, so the response reads as `200 OK` with the
      // `null` body the value comes from, not as the 406 PostgREST answered.
      var success = response
      success.status = .ok
      success.headerFields[.contentLength] = nil
      success.headerFields[.proxyStatus] = nil
      return try decoded(success, body: Data("null".utf8))
    }
    throw error
  }

  func httpRequest(for configuration: PostgrestClient.Configuration) -> HTTPTypes.HTTPRequest {
    var fields = headerFields
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
    if let clientInfo = fields[.xClientInfo] {
      fields[.xClientInfo] = ClientInfoFeature.clientInfo(clientInfo, adding: clientInfoFeatures)
    }
    if let schema = configuration.schema {
      fields[method == .get || method == .head ? .acceptProfile : .contentProfile] = schema
    }
    return HTTPTypes.HTTPRequest(
      method: method,
      url: configuration.url.appendingPathComponent(relation).appendingQueryItems(
        leadingQuery + query),
      headerFields: fields
    )
  }
}

extension PostgrestClient {
  func makeRequest(
    _ relation: String,
    method: HTTPTypes.HTTPRequest.Method = .get
  ) -> _PostgrestRequest {
    _PostgrestRequest(
      method: method, relation: relation,
      headerFields: PostgrestClient.Configuration.defaultHeaders.merging(
        with: configuration.headers))
  }
}

extension HTTPField.Name {
  static let acceptProfile = Self("Accept-Profile")!
  static let contentProfile = Self("Content-Profile")!
  static let proxyStatus = Self("Proxy-Status")!
}
