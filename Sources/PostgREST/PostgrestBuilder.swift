import ConcurrencyExtras
import Foundation
import Helpers
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The builder class for creating and executing requests to a PostgREST server.
@MainActor
public class PostgrestBuilder {
  /// The configuration for the PostgREST client.
  let configuration: PostgrestClient.Configuration
  let http: any HTTPClientType

  var request: Helpers.HTTPRequest

  /// The options for fetching data from the PostgREST server.
  var fetchOptions: FetchOptions

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

    self.request = request
    self.fetchOptions = FetchOptions()
  }

  convenience init(_ other: PostgrestBuilder) {
    self.init(
      configuration: other.configuration,
      request: other.request
    )
  }

  /// Set a HTTP header for the request.
  @discardableResult
  public func setHeader(name: String, value: String) -> Self {
    return self.setHeader(name: .init(name)!, value: value)
  }

  /// Set a HTTP header for the request.
  @discardableResult
  internal func setHeader(name: HTTPField.Name, value: String) -> Self {
    request.headers[name] = value
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
    fetchOptions = options

    if fetchOptions.head {
      request.method = .head
    }

    if let count = fetchOptions.count {
      if let prefer = request.headers[.prefer] {
        request.headers[.prefer] = "\(prefer),count=\(count.rawValue)"
      } else {
        request.headers[.prefer] = "count=\(count.rawValue)"
      }
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

    let response = try await http.send(request)

    guard 200 ..< 300 ~= response.statusCode else {
      if let error = try? configuration.decoder.decode(PostgrestError.self, from: response.data) {
        throw error
      }

      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    let value = try decode(response.data)
    return PostgrestResponse(data: response.data, response: response.underlyingResponse, value: value)
  }
}

extension HTTPField.Name {
  static let acceptProfile = Self("Accept-Profile")!
  static let contentProfile = Self("Content-Profile")!
}
