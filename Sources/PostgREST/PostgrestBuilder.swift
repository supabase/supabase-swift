import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The builder class for creating and executing requests to a PostgREST server.
public class PostgrestBuilder: @unchecked Sendable {
  /// The configuration for the PostgREST client.
  let configuration: PostgrestClient.Configuration

  struct MutableState {
    var request: Request

    /// The options for fetching data from the PostgREST server.
    var fetchOptions: FetchOptions
  }

  let mutableState: ActorIsolated<MutableState>

  init(
    configuration: PostgrestClient.Configuration,
    request: Request
  ) {
    self.configuration = configuration

    mutableState = ActorIsolated(
      MutableState(
        request: request,
        fetchOptions: FetchOptions()
      )
    )
  }

  convenience init(_ other: PostgrestBuilder) {
    self.init(
      configuration: other.configuration,
      request: other.mutableState.value.request
    )
  }

  /// Executes the request and returns a response of type Void.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<Void>` instance representing the response.
  @discardableResult
  public func execute(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<Void> {
    mutableState.withValue {
      $0.fetchOptions = options
    }

    return try await execute { _ in () }
  }

  /// Executes the request and returns a response of the specified type.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<T>` instance representing the response.
  @discardableResult
  public func execute<T: Decodable>(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<T> {
    mutableState.withValue {
      $0.fetchOptions = options
    }

    return try await execute { [configuration] data in
      try configuration.decoder.decode(T.self, from: data)
    }
  }

  private func execute<T>(decode: (Data) throws -> T) async throws -> PostgrestResponse<T> {
    let urlRequest = try mutableState.withValue {
      if $0.fetchOptions.head {
        $0.request.method = .head
      }

      if let count = $0.fetchOptions.count {
        if let prefer = $0.request.headers["Prefer"] {
          $0.request.headers["Prefer"] = "\(prefer),count=\(count.rawValue)"
        } else {
          $0.request.headers["Prefer"] = "count=\(count.rawValue)"
        }
      }

      if $0.request.headers["Accept"] == nil {
        $0.request.headers["Accept"] = "application/json"
      }
      $0.request.headers["Content-Type"] = "application/json"

      if let schema = configuration.schema {
        if $0.request.method == .get || $0.request.method == .head {
          $0.request.headers["Accept-Profile"] = schema
        } else {
          $0.request.headers["Content-Profile"] = schema
        }
      }

      return try $0.request.urlRequest(withBaseURL: configuration.url)
    }

    let (data, response) = try await configuration.fetch(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard 200 ..< 300 ~= httpResponse.statusCode else {
      let error = try configuration.decoder.decode(PostgrestError.self, from: data)
      throw error
    }

    let value = try decode(data)
    return PostgrestResponse(data: data, response: httpResponse, value: value)
  }
}
