import ConcurrencyExtras
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The builder class for creating and executing requests to a PostgREST server.
///
/// - Note: Thread Safety: This class is `@unchecked Sendable` because all mutable state
///   is protected by `LockIsolated`. Access to `mutableState` is always through `withValue`.
///
/// - Important: While this class is `Sendable`, individual builder instances should not be
///   modified concurrently from multiple tasks. Create separate builder chains for concurrent operations.
public class PostgrestBuilder: @unchecked Sendable {
  /// The configuration for the PostgREST client.
  let configuration: PostgrestClient.Configuration
  let http: any HTTPClientType

  struct MutableState {
    var request: Helpers.HTTPRequest

    /// The options for fetching data from the PostgREST server.
    var fetchOptions: FetchOptions

    /// Whether automatic retries are enabled for this request.
    var retryEnabled: Bool
  }

  let mutableState: LockIsolated<MutableState>

  init(
    configuration: PostgrestClient.Configuration,
    request: Helpers.HTTPRequest
  ) {
    self.configuration = configuration

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(fetch: configuration.fetch, interceptors: interceptors)

    mutableState = LockIsolated(
      MutableState(
        request: request,
        fetchOptions: FetchOptions(),
        retryEnabled: configuration.retryEnabled
      )
    )
  }

  convenience init(_ other: PostgrestBuilder) {
    self.init(
      configuration: other.configuration,
      request: other.mutableState.value.request
    )
    mutableState.withValue { $0.retryEnabled = other.mutableState.value.retryEnabled }
  }

  /// Set a HTTP header for the request.
  @discardableResult
  public func setHeader(name: String, value: String) -> Self {
    return self.setHeader(name: .init(name)!, value: value)
  }

  /// Set a HTTP header for the request.
  @discardableResult
  internal func setHeader(name: HTTPField.Name, value: String) -> Self {
    mutableState.withValue {
      $0.request.headers[name] = value
    }
    return self
  }

  /// Controls whether automatic retries are enabled for this request.
  ///
  /// When enabled, the request will be retried up to 3 times with exponential backoff on
  /// transient errors (HTTP 520, network errors) for idempotent methods (GET, HEAD).
  /// - Parameter enabled: Pass `false` to disable retries for this request.
  @discardableResult
  public func retry(enabled: Bool) -> Self {
    mutableState.withValue { $0.retryEnabled = enabled }
    return self
  }

  /// Executes the request and returns a response of type Void.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<Void>` instance representing the response.
  @discardableResult
  public func execute(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<Void> {
    try await execute(options: options) { _ in () }
  }

  /// Executes the request and returns a response of the specified type.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<T>` instance representing the response.
  @discardableResult
  public func execute<T: Decodable>(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<T> {
    try await execute(options: options) { [configuration] data in
      do {
        return try configuration.decoder.decode(T.self, from: data)
      } catch {
        configuration.logger?.error("Fail to decode type '\(T.self) with error: \(error)")
        throw error
      }
    }
  }

  private func execute<T>(
    options: FetchOptions,
    decode: (Data) throws -> T
  ) async throws -> PostgrestResponse<T> {
    let (request, retryEnabled) = mutableState.withValue {
      $0.fetchOptions = options

      if $0.fetchOptions.head {
        $0.request.method = .head
      }

      if let count = $0.fetchOptions.count {
        $0.request.headers.appendOrUpdate(.prefer, value: "count=\(count.rawValue)")
      }

      if $0.request.headers[.accept] == nil {
        $0.request.headers[.accept] = "application/json"
      }
      $0.request.headers[.contentType] = "application/json"

      if let schema = configuration.schema {
        if $0.request.method == .get || $0.request.method == .head {
          $0.request.headers[.acceptProfile] = schema
        } else {
          $0.request.headers[.contentProfile] = schema
        }
      }

      return ($0.request, $0.retryEnabled)
    }

    let isIdempotent = request.method == .get || request.method == .head
    let shouldRetry = retryEnabled && isIdempotent
    let maxRetries = 3

    var attempt = 0
    while true {
      var requestToSend = request
      if attempt > 0 {
        requestToSend.headers[.xRetryCount] = "\(attempt)"
      }

      let response: Helpers.HTTPResponse
      do {
        response = try await http.send(requestToSend)
      } catch {
        if shouldRetry && attempt < maxRetries {
          try await _clock.sleep(for: retryDelay(attempt: attempt))
          attempt += 1
          continue
        }
        throw error
      }

      guard 200..<300 ~= response.statusCode else {
        if shouldRetry && response.statusCode == 520 && attempt < maxRetries {
          try await _clock.sleep(for: retryDelay(attempt: attempt))
          attempt += 1
          continue
        }

        if let error = try? configuration.decoder.decode(PostgrestError.self, from: response.data) {
          throw error
        }
        throw HTTPError(data: response.data, response: response.underlyingResponse)
      }

      let value = try decode(response.data)
      return PostgrestResponse(
        data: response.data, response: response.underlyingResponse, value: value)
    }
  }

  private func retryDelay(attempt: Int) -> TimeInterval {
    min(pow(2.0, Double(attempt)), 30.0)
  }
}

extension HTTPField.Name {
  static let acceptProfile = Self("Accept-Profile")!
  static let contentProfile = Self("Content-Profile")!
  static let xRetryCount = Self("X-Retry-Count")!
}
