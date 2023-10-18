import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi {
  var configuration: StorageClientConfiguration

  public init(configuration: StorageClientConfiguration) {
    self.configuration = configuration
  }

  @discardableResult
  func execute(_ request: Request) async throws -> Response {
    var request = request
    request.headers.merge(configuration.headers) { request, _ in request }
    let urlRequest = try request.urlRequest(withBaseURL: configuration.url)

    let (data, response) = try await configuration.session.fetch(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let error = try configuration.decoder.decode(StorageError.self, from: data)
      throw error
    }

    return Response(data: data, response: httpResponse)
  }
}

extension Request {
  init(path: String, method: String, formData: FormData, options: FileOptions?) {
    var headers = ["Content-Type": formData.contentType]
    headers["Cache-Control"] = options?.cacheControl
    self.init(
      path: path,
      method: method,
      headers: headers,
      body: formData.data
    )
  }
}
