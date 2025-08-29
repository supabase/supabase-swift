import Alamofire
import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The builder class for creating and executing requests to a PostgREST server.
public class PostgrestBuilder: @unchecked Sendable {
  /// The configuration for the PostgREST client.
  let configuration: PostgrestClient.Configuration
  let session: Alamofire.Session

  struct MutableState {
    var request: URLRequest
    var query: Parameters

    /// The options for fetching data from the PostgREST server.
    var fetchOptions: FetchOptions
  }

  let mutableState: LockIsolated<MutableState>

  init(
    configuration: PostgrestClient.Configuration,
    request: URLRequest,
    query: Parameters
  ) {
    self.configuration = configuration
    self.session = configuration.session

    mutableState = LockIsolated(
      MutableState(
        request: request,
        query: query,
        fetchOptions: FetchOptions()
      )
    )
  }

  convenience init(_ other: PostgrestBuilder) {
    self.init(
      configuration: other.configuration,
      request: other.mutableState.value.request,
      query: other.mutableState.value.query
    )
  }

  /// Set a HTTP header for the request.
  @discardableResult
  public func setHeader(name: String, value: String) -> Self {
    mutableState.withValue {
      $0.request.headers[name] = value
    }
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
    let (request, query) = mutableState.withValue {
      $0.fetchOptions = options

      if $0.fetchOptions.head {
        $0.request.method = .head
      }

      if let count = $0.fetchOptions.count {
        $0.request.headers.appendOrUpdate("Prefer", value: "count=\(count.rawValue)")
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

      return ($0.request, $0.query)
    }

    let urlEncoder = URLEncoding(destination: .queryString)

    let response = await session.request(try urlEncoder.encode(request, with: query))
      .validate { request, response, data in
        guard 200..<300 ~= response.statusCode else {

          guard let data else {
            return .failure(AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
          }

          do {
            return .failure(
              try self.configuration.decoder.decode(PostgrestError.self, from: data)
            )
          } catch {
            return .failure(HTTPError(data: data, response: response))
          }
        }
        return .success(())
      }
      .serializingData()
      .response

    let value = try decode(response.result.get())

    return PostgrestResponse(
      data: response.data ?? Data(), response: response.response!, value: value)
  }
}
