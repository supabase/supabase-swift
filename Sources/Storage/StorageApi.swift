import Foundation
import HTTPClient
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let client: Client

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

    self.configuration = configuration

    let transport = URLSessionTransport(configuration: .init(session: configuration.session))

    var middlewares: [any ClientMiddleware] = []
    if let accessToken = configuration.accessToken {
      middlewares.append(AccessTokenMiddleware(accessToken: accessToken))
    }
    if let logger = configuration.logger {
      middlewares.append(SupabaseLoggerMiddleware(logger: logger))
    }

    client = Client(serverURL: configuration.url, transport: transport, middlewares: middlewares)
  }

  @discardableResult
  func execute(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Data? = nil
  ) async throws -> StorageResponse {
    let (response, responseBody) = try await executeStream(
      url: url,
      method: method,
      query: query,
      headers: headers,
      body: body.map(HTTPBody.init)
    )

    let data = try await Data(collecting: responseBody ?? HTTPBody(), upTo: .max)

    guard response.status.kind == HTTPTypes.HTTPResponse.Status.Kind.successful else {
      if let error = try? configuration.decoder.decode(StorageError.self, from: data) {
        throw error
      }
      throw StorageHTTPError(data: data, response: response)
    }

    return StorageResponse(data: data, response: response)
  }

  @discardableResult
  func executeMultipart(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    multipartFormData: MultipartFormData,
    usingThreshold encodingMemoryThreshold: UInt64 = MultipartFormData.encodingMemoryThreshold
  ) async throws -> StorageResponse {
    let request = try buildRequest(url: url, method: method, query: query, headers: headers)
    let (response, responseBody) = try await client.send(
      multipartFormData: multipartFormData,
      with: request,
      usingThreshold: encodingMemoryThreshold
    )

    let data = try await Data(collecting: responseBody ?? HTTPBody(), upTo: .max)

    guard response.status.kind == HTTPTypes.HTTPResponse.Status.Kind.successful else {
      if let error = try? configuration.decoder.decode(StorageError.self, from: data) {
        throw error
      }
      throw StorageHTTPError(data: data, response: response)
    }

    return StorageResponse(data: data, response: response)
  }

  func executeStream(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: HTTPBody? = nil
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = try buildRequest(url: url, method: method, query: query, headers: headers)

    if body != nil, request.headerFields[.contentType] == nil {
      request.headerFields[.contentType] = "application/json"
    }

    return try await client.send(request, body: body)
  }

  private func buildRequest(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem],
    headers: HTTPFields
  ) throws -> HTTPTypes.HTTPRequest {
    // Merge default headers (client-level) with request headers.
    var headerFields = HTTPFields(configuration.headers).merging(with: headers)

    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var queryItems = (components?.queryItems ?? []) + query

    // Normalize query items in the URL (avoid duplicates with same name).
    var normalized: [URLQueryItem] = []
    for item in queryItems {
      if let index = normalized.firstIndex(where: { $0.name == item.name }) {
        normalized[index] = item
      } else {
        normalized.append(item)
      }
    }
    queryItems = normalized

    // Build a path relative to the configured base URL path to avoid duplicating it.
    let basePath = configuration.url.path
    let absolutePath = url.path
    let relativePath: String
    if absolutePath.hasPrefix(basePath) {
      relativePath =
        "/"
        + absolutePath.dropFirst(basePath.count).trimmingCharacters(
          in: CharacterSet(charactersIn: "/"))
    } else {
      relativePath = absolutePath.hasPrefix("/") ? absolutePath : "/\(absolutePath)"
    }

    var path = relativePath
    if !queryItems.isEmpty {
      var tmp = URLComponents()
      tmp.path = path
      tmp.queryItems = queryItems
      path = tmp.string ?? path
    }

    // Ensure path has a leading slash.
    if !path.hasPrefix("/") {
      path = "/\(path)"
    }

    // Prevent nil pseudo-fields for scheme/authority; URLSessionTransport will combine with baseURL.
    return HTTPTypes.HTTPRequest(
      method: method,
      scheme: nil,
      authority: nil,
      path: path,
      headerFields: headerFields
    )
  }
}

public struct StorageResponse: Sendable {
  public let data: Data
  public let response: HTTPTypes.HTTPResponse

  public init(data: Data, response: HTTPTypes.HTTPResponse) {
    self.data = data
    self.response = response
  }

  public func decoded<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder
  ) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}

public struct StorageHTTPError: Error, LocalizedError, Sendable {
  public let data: Data
  public let response: HTTPTypes.HTTPResponse

  public init(data: Data, response: HTTPTypes.HTTPResponse) {
    self.data = data
    self.response = response
  }

  public var errorDescription: String? {
    var message = "Status Code: \(response.status.code)"
    if let body = String(data: data, encoding: .utf8) {
      message += " Body: \(body)"
    }
    return message
  }
}

private struct AccessTokenMiddleware: ClientMiddleware {
  let accessToken: @Sendable () async throws -> String?

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    if let token = try await accessToken() {
      request.headerFields[.authorization] = "Bearer \(token)"
    }
    return try await next(request, body, baseURL)
  }
}

private struct SupabaseLoggerMiddleware: ClientMiddleware {
  let logger: any SupabaseLogger

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    logger.verbose("⬆️ \(request.method.rawValue) \(request.path ?? "<nil>")")
    let (response, responseBody) = try await next(request, body, baseURL)
    logger.verbose("⬇️ \(response.status.code) \(response.status.reasonPhrase)")
    return (response, responseBody)
  }
}
