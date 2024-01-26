import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let http: HTTPClient

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }
    self.configuration = configuration
    http = HTTPClient(logger: configuration.logger, fetchHandler: configuration.session.fetch)
  }

  @discardableResult
  func execute(_ request: Request) async throws -> Response {
    var request = request
    request.headers.merge(configuration.headers) { request, _ in request }

    let response = try await http.fetch(request, baseURL: configuration.url)

    guard (200 ..< 300).contains(response.statusCode) else {
      let error = try configuration.decoder.decode(StorageError.self, from: response.data)
      throw error
    }

    return response
  }
}

extension Request {
  init(
    path: String, method: Method, formData: FormData, options: FileOptions,
    headers: [String: String] = [:]
  ) {
    var headers = headers
    if headers["Content-Type"] == nil {
      headers["Content-Type"] = formData.contentType
    }
    if headers["Cache-Control"] == nil {
      headers["Cache-Control"] = "max-age=\(options.cacheControl)"
    }
    self.init(
      path: path,
      method: method,
      headers: headers,
      body: formData.data
    )
  }
}
