import ConcurrencyExtras
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Base class for Storage API operations.
///
/// - Note: Thread Safety: This class is `@unchecked Sendable` because all mutable state
///   is protected by `LockIsolated`. The `configuration` property is immutable (`let`),
///   while mutable headers are managed separately via `mutableState`.
public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private struct MutableState {
    var headers: [String: String]
  }

  private let mutableState: LockIsolated<MutableState>
  private let http: any HTTPClientType

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(configuration.url)")
      }

      let regex = try! NSRegularExpression(pattern: "supabase.(co|in|red)$")

      let isSupabaseHost =
        regex.firstMatch(in: host, range: NSRange(location: 0, length: host.utf16.count)) != nil

      if isSupabaseHost, !host.contains("storage.supabase.") {
        components.host = host.replacingOccurrences(of: "supabase.", with: "storage.supabase.")
      }

      configuration.url = components.url!
    }

    let initialHeaders = configuration.headers
    self.configuration = configuration
    self.mutableState = LockIsolated(MutableState(headers: initialHeaders))

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(
      fetch: configuration.session.fetch,
      interceptors: interceptors
    )
  }

  /// Sets an HTTP header for subsequent requests.
  ///
  /// This method is thread-safe and creates a copy of the headers to avoid mutating shared state.
  ///
  /// - Parameters:
  ///   - name: The name of the header to set.
  ///   - value: The value of the header.
  /// - Returns: `self` to allow method chaining.
  @discardableResult
  public func setHeader(name: String, value: String) -> Self {
    mutableState.withValue { $0.headers[name] = value }
    return self
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    var request = request
    let headers = mutableState.headers
    request.headers = HTTPFields(headers).merging(with: request.headers)

    let response = try await http.send(request)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: response.data
      ) {
        throw error
      }

      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
  }
}

extension Helpers.HTTPRequest {
  init(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem],
    formData: MultipartFormData,
    options: FileOptions,
    headers: HTTPFields = [:]
  ) throws {
    var headers = headers
    if headers[.contentType] == nil {
      headers[.contentType] = formData.contentType
    }
    if headers[.cacheControl] == nil {
      headers[.cacheControl] = "max-age=\(options.cacheControl)"
    }
    try self.init(
      url: url,
      method: method,
      query: query,
      headers: headers,
      body: formData.encode()
    )
  }
}
