import Alamofire
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let session: Alamofire.Session

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
    self.session = configuration.session
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Data {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

    let urlRequest = request.urlRequest

    return try await session.request(urlRequest)
      .validate { request, response, data in
        guard 200..<300 ~= response.statusCode else {
          guard let data else {
            return .failure(AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
          }

          do {
            return .failure(try self.configuration.decoder.decode(StorageError.self, from: data))
          } catch {
            return .failure(HTTPError(data: data, response: response))
          }
        }
        return .success(())
      }
      .serializingData()
      .value
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
