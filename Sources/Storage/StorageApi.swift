import _Helpers
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let http: any HTTPClientType

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }
    self.configuration = configuration

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(
      fetch: configuration.session.fetch,
      interceptors: interceptors
    )
  }

  @discardableResult
  func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
    var request = request
    request.headers.merge(with: HTTPHeaders(configuration.headers))

    let response = try await http.send(request)

    guard (200 ..< 300).contains(response.statusCode) else {
      if let error = try? configuration.decoder.decode(StorageError.self, from: response.data) {
        throw error
      }

      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
  }
}

extension HTTPRequest {
  init(
    url: URL,
    method: HTTPMethod,
    query: [URLQueryItem],
    formData: FormData,
    options: FileOptions,
    headers: HTTPHeaders = [:]
  ) {
    var headers = headers
    if headers["Content-Type"] == nil {
      headers["Content-Type"] = formData.contentType
    }
    if headers["Cache-Control"] == nil {
      headers["Cache-Control"] = "max-age=\(options.cacheControl)"
    }
    self.init(
      url: url,
      method: method,
      query: query,
      headers: headers,
      body: formData.data
    )
  }
}
