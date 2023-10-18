import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi {
  var configuration: StorageClientConfiguration

  var url: String {
    configuration.url.absoluteString
  }
  var headers: [String: String] {
    configuration.headers
  }
  var session: StorageHTTPSession {
    configuration.session
  }

  init(configuration: StorageClientConfiguration) {
    self.configuration = configuration
  }

  @discardableResult
  func execute(_ request: Request) async throws -> Response {
    var request = request
    request.headers.merge(configuration.headers) { _, new in new }
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

  internal enum HTTPMethod: String {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case connect = "CONNECT"
    case options = "OPTIONS"
    case trace = "TRACE"
    case patch = "PATCH"
  }

  internal func fetch<T: Decodable>(
    url: URL,
    method: HTTPMethod = .post,
    formData: FormData,
    headers: [String: String]? = nil,
    fileOptions: FileOptions? = nil,
    jsonSerialization: Bool = true
  ) async throws -> T {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue

    if let fileOptions = fileOptions {
      request.setValue(fileOptions.cacheControl, forHTTPHeaderField: "Cache-Control")
    }

    var allHTTPHeaderFields = self.headers
    if let headers = headers {
      allHTTPHeaderFields.merge(headers) { $1 }
    }

    allHTTPHeaderFields.forEach { key, value in
      request.setValue(value, forHTTPHeaderField: key)
    }

    request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")

    let (data, response) = try await session.upload(request, formData.data)
    guard let httpResonse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    return try parse(response: data, statusCode: httpResonse.statusCode)
  }

  private func parse<T: Decodable>(response: Data, statusCode: Int) throws -> T {
    if 200..<300 ~= statusCode {
      return try JSONDecoder().decode(T.self, from: response)
    }

    throw try JSONDecoder().decode(StorageError.self, from: response)
  }
}
