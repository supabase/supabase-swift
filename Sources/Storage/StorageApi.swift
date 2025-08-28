import Alamofire
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct NoopParameter: Encodable, Sendable {}

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

  private let urlQueryEncoder: any ParameterEncoding = URLEncoding.queryString
  private var defaultEncoder: any ParameterEncoder {
    JSONParameterEncoder(encoder: configuration.encoder)
  }

  @discardableResult
  func execute<RequestBody: Encodable & Sendable>(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders = [:],
    query: Parameters? = nil,
    body: RequestBody? = NoopParameter(),
    encoder: (any ParameterEncoder)? = nil
  ) throws -> DataRequest {
    var request = try makeRequest(url, method: method, headers: headers, query: query)

    if RequestBody.self != NoopParameter.self {
      request = try (encoder ?? defaultEncoder).encode(body, into: request)
    }

    return session.request(request)
      .validate { _, response, data in
        self.validate(response: response, data: data ?? Data())
      }
  }

  func upload(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders = [:],
    query: Parameters? = nil,
    multipartFormData: @escaping (MultipartFormData) -> Void,
  ) throws -> UploadRequest {
    let request = try makeRequest(url, method: method, headers: headers, query: query)
    return session.upload(multipartFormData: multipartFormData, with: request)
      .validate { _, response, data in
        self.validate(response: response, data: data ?? Data())
      }
  }

  private func makeRequest(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders = [:],
    query: Parameters? = nil
  ) throws -> URLRequest {
    // Merge configuration headers with request headers
    var mergedHeaders = HTTPHeaders(configuration.headers)
    for header in headers {
      mergedHeaders[header.name] = header.value
    }
    
    let request = try URLRequest(url: url, method: method, headers: mergedHeaders)
    return try urlQueryEncoder.encode(request, with: query)
  }

  private func validate(response: HTTPURLResponse, data: Data) -> DataRequest.ValidationResult {
    guard 200..<300 ~= response.statusCode else {
      do {
        return .failure(try self.configuration.decoder.decode(StorageError.self, from: data))
      } catch {
        return .failure(HTTPError(data: data, response: response))
      }
    }
    return .success(())
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
