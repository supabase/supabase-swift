import Foundation
import HTTPTypes
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let http: any HTTPClientType

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers[.xClientInfo] == nil {
      configuration.headers[.xClientInfo] = "storage-swift/\(version)"
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
  func execute(
    for request: HTTPRequest,
    from bodyData: Data?
  ) async throws -> (Data, HTTPResponse) {
    var request = request
    request.headerFields = configuration.headers.merging(with: request.headerFields)

    let (data, response) = try await http.send(request, bodyData)

    guard (200..<300).contains(response.status.code) else {
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: data
      ) {
        throw error
      }

      throw HTTPError(data: data, response: response)
    }

    return (data, response)
  }
}

extension HTTPRequest {
  init(
    method: HTTPRequest.Method,
    url: URL,
    options: FileOptions,
    headers: HTTPFields = [:],
    formData: MultipartFormData
  ) throws {
    var headers = headers
    if headers[.contentType] == nil {
      headers[.contentType] = formData.contentType
    }
    if headers[.cacheControl] == nil {
      headers[.cacheControl] = "max-age=\(options.cacheControl)"
    }

    self.init(
      method: method,
      url: url,
      headerFields: headers
    )
  }
}
