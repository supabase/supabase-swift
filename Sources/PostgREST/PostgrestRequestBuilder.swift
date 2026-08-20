//
//  PostgrestRequestBuilder.swift
//  PostgREST
//
//  Created by Guilherme Souza on 20/08/26.
//

public import Foundation
import HTTPTypes
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A marker protocol conformed to by every phase whose builder can execute a request and set
/// per-request headers/retry behavior.
///
/// Conform a phase type to this — or, more commonly, to ``PostgrestTransformablePhase`` or
/// ``PostgrestFilterablePhase``, both of which refine it — to grant `setHeader`/`retry`/`execute`
/// on ``PostgrestRequestBuilder`` when `Phase` is that type.
public protocol PostgrestExecutablePhase {}

/// A marker protocol for phases that can still apply ordering, pagination, and response-format
/// transformations. Refines ``PostgrestExecutablePhase``, so every transformable phase is also
/// executable.
public protocol PostgrestTransformablePhase: PostgrestExecutablePhase {}

/// A marker protocol for phases that can still apply WHERE-clause filters. Refines
/// ``PostgrestTransformablePhase``, so every filterable phase is also transformable and
/// executable.
public protocol PostgrestFilterablePhase: PostgrestTransformablePhase {}

/// The phase immediately after ``PostgrestClient/from(_:)``, before an operation
/// (`select`/`insert`/`update`/`upsert`/`delete`) has been chosen.
///
/// This phase conforms to none of the capability protocols: you cannot filter, transform, set
/// headers, or execute until you pick an operation.
public enum PostgrestQueryPhase {}

/// The phase after a filterable operation has been chosen (or after
/// ``PostgrestClient/rpc(_:params:head:get:count:)``). Supports filtering, transforming, and
/// executing.
public enum PostgrestFilterPhase: PostgrestFilterablePhase {}

/// The phase after any transformation (`order`, `limit`, `single`, ...) has been applied.
/// Supports further transformations and executing, but no longer filtering.
public enum PostgrestTransformPhase: PostgrestTransformablePhase {}

/// Builder for all PostgREST requests, parameterized by the request's current phase.
///
/// Don't reference this generic type directly — use the phase-specific type aliases instead:
/// ``PostgrestQueryBuilder``, ``PostgrestFilterBuilder``, and ``PostgrestTransformBuilder``. The
/// `Phase` parameter is a compile-time-only marker (never constructed) that determines which
/// methods are available: filter methods require ``PostgrestFilterablePhase``, transform methods
/// require ``PostgrestTransformablePhase``, and `setHeader`/`retry`/`execute` require
/// ``PostgrestExecutablePhase``. You don't construct this type directly — call
/// ``PostgrestClient/from(_:)`` or ``PostgrestClient/rpc(_:params:head:get:count:)`` and chain
/// from there.
///
/// ## Topics
///
/// ### Setting Headers
///
/// - ``setHeader(name:value:)``
///
/// ### Configuring Retries
///
/// - ``retry(enabled:)``
///
/// ### Executing the Request
///
/// - ``execute(options:)->PostgrestResponse<Void>``
/// - ``execute(options:decoder:)``
public struct PostgrestRequestBuilder<Phase>: Sendable {
  let configuration: PostgrestClient.Configuration
  let http: any HTTPClientType
  let clock: any Clock<Duration>

  var request: Helpers.HTTPRequest

  /// Whether automatic retries are enabled for this request.
  var retryEnabled: Bool

  /// An error to throw when execute() is called, set when an invalid method combination is
  /// detected.
  var pendingError: String?

  /// Whether a `PGRST116` error should be returned as a `nil` value instead of being thrown.
  var isMaybeSingle: Bool = false

  init(
    configuration: PostgrestClient.Configuration,
    request: Helpers.HTTPRequest,
    clock: any Clock<Duration>
  ) {
    self.configuration = configuration
    self.clock = clock

    let interceptors: [any HTTPClientInterceptor] = [
      LoggerInterceptor(logger: configuration.logger)
    ]
    self.http = HTTPClient(fetch: configuration.fetch, interceptors: interceptors)

    self.request = request
    self.retryEnabled = configuration.retryEnabled
    self.pendingError = nil
    self.isMaybeSingle = false
  }

  /// Recasts an existing builder to a different phase, preserving every field except `request`.
  ///
  /// Every method that changes phase (e.g. `select`/`insert` moving from ``PostgrestQueryPhase``
  /// to ``PostgrestFilterPhase``, or any transform method moving to ``PostgrestTransformPhase``)
  /// goes through this initializer instead of resetting state, because `pendingError` and
  /// `isMaybeSingle` must survive a phase change — e.g. `.maybeSingle().order(...)` must not lose
  /// the `isMaybeSingle` flag just because `order` also changes the phase.
  init<From>(carryingFrom other: PostgrestRequestBuilder<From>, request: Helpers.HTTPRequest) {
    self.configuration = other.configuration
    self.http = other.http
    self.clock = other.clock
    self.request = request
    self.retryEnabled = other.retryEnabled
    self.pendingError = other.pendingError
    self.isMaybeSingle = other.isMaybeSingle
  }
}

/// Builder for SELECT, INSERT, UPDATE, UPSERT, and DELETE operations on a table or view.
///
/// This is ``PostgrestRequestBuilder`` specialized to ``PostgrestQueryPhase``, the phase a request
/// starts in before an operation has been chosen.
///
/// Obtain one by calling ``PostgrestClient/from(_:)`` and then chain one of the operation methods.
/// Most methods return a ``PostgrestFilterBuilder`` so you can narrow the affected rows with WHERE
/// clauses before executing.
///
/// ```swift
/// // INSERT a single row
/// try await client
///   .from("todos")
///   .insert(["task": "Buy milk", "done": false])
///   .execute()
///
/// // SELECT with a filter
/// let todos: [Todo] = try await client
///   .from("todos")
///   .select()
///   .eq("done", value: false)
///   .execute()
///   .value
/// ```
///
/// ## Topics
///
/// ### Querying Rows
///
/// - ``PostgrestRequestBuilder/select(_:head:count:)``
///
/// ### Inserting Rows
///
/// - ``PostgrestRequestBuilder/insert(_:returning:count:encoder:)``
///
/// ### Updating Rows
///
/// - ``PostgrestRequestBuilder/update(_:returning:count:encoder:)``
///
/// ### Upsert Rows
///
/// - ``PostgrestRequestBuilder/upsert(_:onConflict:returning:count:ignoreDuplicates:encoder:)``
///
/// ### Deleting Rows
///
/// - ``PostgrestRequestBuilder/delete(returning:count:)``
public typealias PostgrestQueryBuilder = PostgrestRequestBuilder<PostgrestQueryPhase>

/// Builder for applying WHERE-clause filters to a PostgREST query, before transforming or
/// executing it.
///
/// This is ``PostgrestRequestBuilder`` specialized to ``PostgrestFilterPhase``.
///
/// Obtain one from ``PostgrestRequestBuilder/select(_:head:count:)``,
/// ``PostgrestRequestBuilder/insert(_:returning:count:encoder:)``,
/// ``PostgrestRequestBuilder/update(_:returning:count:encoder:)``, or another write method on
/// ``PostgrestQueryBuilder``, or from ``PostgrestClient/rpc(_:params:head:get:count:)``. Chain one
/// or more filter methods, then call
/// ``PostgrestRequestBuilder/execute(options:decoder:)`` to send the request.
///
/// All filter methods return `Self` so they can be freely chained:
///
/// ```swift
/// let results: [Todo] = try await client
///   .from("todos")
///   .select()
///   .eq("done", value: false)
///   .order("created_at", ascending: false)
///   .limit(20)
///   .execute()
///   .value
/// ```
///
/// ## Topics
///
/// ### Equality Filters
///
/// - ``PostgrestRequestBuilder/eq(_:value:)``
/// - ``PostgrestRequestBuilder/neq(_:value:)``
/// - ``PostgrestRequestBuilder/is(_:value:)``
/// - ``PostgrestRequestBuilder/isDistinct(_:value:)``
/// - ``PostgrestRequestBuilder/in(_:values:)``
/// - ``PostgrestRequestBuilder/notIn(_:values:)``
/// - ``PostgrestRequestBuilder/match(_:)``
///
/// ### Comparison Filters
///
/// - ``PostgrestRequestBuilder/gt(_:value:)``
/// - ``PostgrestRequestBuilder/gte(_:value:)``
/// - ``PostgrestRequestBuilder/lt(_:value:)``
/// - ``PostgrestRequestBuilder/lte(_:value:)``
///
/// ### Pattern Matching Filters
///
/// - ``PostgrestRequestBuilder/like(_:pattern:)``
/// - ``PostgrestRequestBuilder/likeAllOf(_:patterns:)``
/// - ``PostgrestRequestBuilder/likeAnyOf(_:patterns:)``
/// - ``PostgrestRequestBuilder/ilike(_:pattern:)``
/// - ``PostgrestRequestBuilder/iLikeAllOf(_:patterns:)``
/// - ``PostgrestRequestBuilder/iLikeAnyOf(_:patterns:)``
/// - ``PostgrestRequestBuilder/match(_:pattern:)``
/// - ``PostgrestRequestBuilder/imatch(_:pattern:)``
///
/// ### Array and Range Filters
///
/// - ``PostgrestRequestBuilder/contains(_:value:)``
/// - ``PostgrestRequestBuilder/containedBy(_:value:)``
/// - ``PostgrestRequestBuilder/overlaps(_:value:)``
/// - ``PostgrestRequestBuilder/rangeLt(_:range:)``
/// - ``PostgrestRequestBuilder/rangeGt(_:range:)``
/// - ``PostgrestRequestBuilder/rangeGte(_:range:)``
/// - ``PostgrestRequestBuilder/rangeLte(_:range:)``
/// - ``PostgrestRequestBuilder/rangeAdjacent(_:range:)``
///
/// ### Full-Text Search
///
/// - ``PostgrestRequestBuilder/textSearch(_:query:config:type:)``
/// - ``PostgrestRequestBuilder/fts(_:query:config:)``
///
/// ### Logical Operators
///
/// - ``PostgrestRequestBuilder/not(_:operator:value:)``
/// - ``PostgrestRequestBuilder/or(_:referencedTable:)``
/// - ``PostgrestRequestBuilder/filter(_:operator:value:)``
///
/// ### Operators
///
/// - ``PostgrestOperator``
public typealias PostgrestFilterBuilder = PostgrestRequestBuilder<PostgrestFilterPhase>

/// Builder for ordering, pagination, and response-format transformations, before executing a
/// PostgREST request.
///
/// This is ``PostgrestRequestBuilder`` specialized to ``PostgrestTransformPhase``. It sits between
/// ``PostgrestFilterBuilder`` (WHERE clauses) and
/// ``PostgrestRequestBuilder/execute(options:decoder:)`` (sending the request). All
/// transformation methods narrow the builder to ``PostgrestTransformPhase``, so once you call one
/// you can no longer filter — only transform further or execute.
///
/// ```swift
/// let page: [Todo] = try await client
///   .from("todos")
///   .select()
///   .order("created_at", ascending: false)
///   .range(from: 0, to: 9)
///   .execute()
///   .value
/// ```
///
/// ## Topics
///
/// ### Returning Modified Rows
///
/// - ``PostgrestRequestBuilder/select(_:)``
///
/// ### Ordering and Pagination
///
/// - ``PostgrestRequestBuilder/order(_:ascending:nullsFirst:referencedTable:)``
/// - ``PostgrestRequestBuilder/limit(_:referencedTable:)``
/// - ``PostgrestRequestBuilder/range(from:to:referencedTable:)``
///
/// ### Response Format
///
/// - ``PostgrestRequestBuilder/single()``
/// - ``PostgrestRequestBuilder/maybeSingle()``
/// - ``PostgrestRequestBuilder/csv()``
/// - ``PostgrestRequestBuilder/geojson()``
/// - ``PostgrestRequestBuilder/stripNulls()``
///
/// ### Query Analysis
///
/// - ``PostgrestRequestBuilder/explain(analyze:verbose:settings:buffers:wal:format:)``
///
/// ### Limiting Affected Rows
///
/// - ``PostgrestRequestBuilder/maxAffected(_:)``
///
/// ### Testing Mutations
///
/// - ``PostgrestRequestBuilder/dryRun()``
public typealias PostgrestTransformBuilder = PostgrestRequestBuilder<PostgrestTransformPhase>

/// A type-erased PostgREST builder that can execute a request and set per-request
/// headers/retry behavior, regardless of its concrete phase.
///
/// ``PostgrestFilterBuilder`` and ``PostgrestTransformBuilder`` both conform to this
/// automatically; ``PostgrestQueryBuilder`` does not, since it hasn't had an operation
/// (`select`/`insert`/`update`/`upsert`/`delete`) applied yet. Use this when you need to accept
/// "any executable PostgREST builder" regardless of which filter/transform methods were chained
/// to produce it.
public protocol PostgrestExecutableBuilder: Sendable {
  /// See ``PostgrestRequestBuilder/execute(options:)->PostgrestResponse<Void>``.
  func execute(options: FetchOptions) async throws -> PostgrestResponse<Void>

  /// See ``PostgrestRequestBuilder/execute(options:decoder:)``.
  func execute<T: Decodable>(options: FetchOptions, decoder: JSONDecoder?) async throws
    -> PostgrestResponse<T>
}

extension PostgrestRequestBuilder: PostgrestExecutableBuilder
where Phase: PostgrestExecutablePhase {}

extension PostgrestRequestBuilder where Phase: PostgrestExecutablePhase {
  /// Adds or replaces a custom HTTP header on the request.
  ///
  /// Use this method to attach arbitrary headers — for example, to pass custom PostgREST
  /// `Prefer` values or to forward user-supplied metadata.
  ///
  /// - Parameters:
  ///   - name: The header field name.
  ///   - value: The header field value.
  /// - Returns: The same builder value so calls can be chained.
  public func setHeader(name: String, value: String) -> Self {
    setHeader(name: .init(name)!, value: value)
  }

  /// Set a HTTP header for the request.
  func setHeader(name: HTTPField.Name, value: String) -> Self {
    var copy = self
    copy.request.headers[name] = value
    return copy
  }

  /// Controls whether automatic retries are enabled for this specific request.
  ///
  /// When enabled, GET and HEAD requests that receive an HTTP 503 or 520 response, or encounter
  /// a network error, are retried up to three times with exponential back-off. The global
  /// default is set via ``PostgrestClient/Configuration/retryEnabled``; this method overrides it
  /// per request.
  ///
  /// - Parameter enabled: Pass `false` to disable retries for this request.
  /// - Returns: The same builder value so calls can be chained.
  public func retry(enabled: Bool) -> Self {
    var copy = self
    copy.retryEnabled = enabled
    return copy
  }

  /// Executes the request and discards the response body.
  ///
  /// Use this overload for mutations (INSERT, UPDATE, DELETE) when you do not need the
  /// affected rows, or when you have already called ``PostgrestRequestBuilder/csv()`` or
  /// a similar method that changes the response format.
  ///
  /// - Parameter options: Options controlling whether to include a row count and whether to
  ///   use the HEAD method. Defaults to ``FetchOptions/init(head:count:)``.
  /// - Returns: A ``PostgrestResponse`` whose `value` is `Void`.
  /// - Throws: ``PostgrestError`` if PostgREST returns an error response, or any error thrown by
  ///   the fetch handler.
  @discardableResult
  public func execute(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<Void> {
    try await execute(options: options) { _ in () }
  }

  /// Executes the request and decodes the response body into the inferred type.
  ///
  /// ```swift
  /// let todos: [Todo] = try await client
  ///   .from("todos")
  ///   .select()
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameters:
  ///   - options: Options controlling whether to include a row count and whether to
  ///     use the HEAD method. Defaults to ``FetchOptions/init(head:count:)``.
  ///   - decoder: The `JSONDecoder` used to decode the response body into `T`. Overrides
  ///     ``PostgrestClient/Configuration/decoder`` when non-`nil`. Never used to decode
  ///     ``PostgrestError`` — that always uses a fixed internal decoder.
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `T`.
  /// - Throws: ``PostgrestError`` if PostgREST returns an error response, a decoding error if
  ///   the response body cannot be decoded as `T`, or any error thrown by the fetch handler.
  @discardableResult
  public func execute<T: Decodable>(
    options: FetchOptions = FetchOptions(),
    decoder: JSONDecoder? = nil
  ) async throws -> PostgrestResponse<T> {
    let decoder = decoder ?? configuration.decoder
    return try await execute(options: options) { [configuration] data in
      do {
        return try decoder.decode(T.self, from: data)
      } catch {
        configuration.logger.error("Failed to decode type '\(T.self) with error: \(error)")
        throw error
      }
    }
  }

  private func execute<T>(
    options: FetchOptions,
    decode: @Sendable (Data) throws -> T
  ) async throws -> PostgrestResponse<T> {
    if let message = pendingError {
      throw PostgrestError(message: message)
    }

    var request = self.request

    // Resolve the access token fresh for every request. An `Authorization` header already set
    // on the request — whether from `PostgrestClient.Configuration.headers` or from an explicit
    // `.setHeader("Authorization", ...)` call — always wins over the resolved token.
    if let accessToken = configuration.accessToken, request.headers[.authorization] == nil {
      if let token = try await accessToken() {
        request.headers[.authorization] = "Bearer \(token)"
      }
    }

    if options.head {
      request.method = .head
    }

    if let count = options.count {
      request.headers.appendOrUpdate(.prefer, value: "count=\(count.rawValue)")
    }

    if request.headers[.accept] == nil {
      request.headers[.accept] = "application/json"
    }
    request.headers[.contentType] = "application/json"

    if let schema = configuration.schema {
      if request.method == .get || request.method == .head {
        request.headers[.acceptProfile] = schema
      } else {
        request.headers[.contentProfile] = schema
      }
    }

    var attempt = 0
    while true {
      try Task.checkCancellation()

      var currentRequest = request
      if attempt > 0 {
        currentRequest.headers[.xRetryCount] = "\(attempt)"
      }

      // Separate the network send from decoding so that decode errors are never retried.
      let response: Helpers.HTTPResponse
      do {
        response = try await http.send(currentRequest)
      } catch {
        if shouldRetry(
          request: currentRequest, response: nil, error: error, retryEnabled: retryEnabled,
          attempt: attempt)
        {
          try await clock.sleep(for: .seconds(retryDelay(attempt: attempt)))
          attempt += 1
          continue
        }
        throw error
      }

      if 200..<300 ~= response.statusCode {
        let value = try decode(response.data)
        return PostgrestResponse(
          data: response.data, response: response.underlyingResponse, value: value)
      }

      if shouldRetry(
        request: currentRequest, response: response, error: nil, retryEnabled: retryEnabled,
        attempt: attempt)
      {
        try await clock.sleep(for: .seconds(retryDelay(attempt: attempt)))
        attempt += 1
        continue
      }

      // `PostgrestError`'s fields match PostgREST's JSON keys exactly, so a plain, fixed
      // `JSONDecoder` decodes it regardless of any user-supplied key/date strategy on
      // `configuration.decoder` or a per-call override — those are for user-defined row types.
      if let error = try? JSONDecoder().decode(PostgrestError.self, from: response.data) {
        // `maybeSingle()` turns the "no rows" variant of PGRST116 into a `nil` value, but
        // rethrows the "multiple rows" variant since that indicates a query that should have
        // been scoped to match at most one row.
        if isMaybeSingle, error.code == "PGRST116", error.matchedZeroRows {
          let value = try decode(Data("null".utf8))
          return PostgrestResponse(
            data: response.data, response: response.underlyingResponse, value: value)
        }
        throw error
      }
      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }
  }

  private static var maxDelay: Double { 30.0 }
  private static var maxRetries: Int { 3 }
  private static var retryableMethods: Set<HTTPTypes.HTTPRequest.Method> { [.get, .head] }
  private static var retryableStatusCodes: Set<Int> { [503, 520] }

  /// Check if a request should be retried based on method, status code, and error type.
  private func shouldRetry(
    request: Helpers.HTTPRequest,
    response: Helpers.HTTPResponse?,
    error: (any Error)?,
    retryEnabled: Bool,
    attempt: Int
  ) -> Bool {
    guard retryEnabled, attempt < Self.maxRetries else { return false }
    guard !(error is CancellationError) else { return false }
    guard Self.retryableMethods.contains(request.method) else { return false }

    if let statusCode = response?.statusCode {
      return Self.retryableStatusCodes.contains(statusCode)
    }

    return true
  }

  private func retryDelay(attempt: Int) -> TimeInterval {
    min(pow(2.0, Double(attempt)), Self.maxDelay)
  }
}

extension HTTPField.Name {
  static let acceptProfile = Self("Accept-Profile")!
  static let contentProfile = Self("Content-Profile")!
  static let xRetryCount = Self("X-Retry-Count")!
}

extension PostgrestError {
  /// Whether a `PGRST116` error was caused by the query matching zero rows, as opposed to more
  /// than one row.
  ///
  /// PostgREST reports both cases with the same error code; the row count is only distinguishable
  /// via the `details` message. The exact wording has varied across PostgREST versions, e.g.
  /// "Results contain 0 rows, application/vnd.pgrst.object+json requires 1 row" and "The result
  /// contains 0 rows". Both mention the matched row count immediately before a "row"/"rows" word,
  /// so look for that instead of matching a fixed prefix.
  fileprivate var matchedZeroRows: Bool {
    guard let details else { return false }
    let words = details.split(separator: " ")
    guard let rowsIndex = words.firstIndex(where: { $0.hasPrefix("row") }), rowsIndex > 0,
      let count = Int(words[rowsIndex - 1])
    else { return false }
    return count == 0
  }
}
