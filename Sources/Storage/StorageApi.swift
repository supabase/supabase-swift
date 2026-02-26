import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Base class for Storage API operations.
///
/// - Note: Thread Safety: This class is `@unchecked Sendable` because all stored properties
///   are immutable (`let`) and themselves `Sendable`. No mutable state exists after initialization.
public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  let http: any HTTPSession

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
    http = configuration.session
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

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

  @discardableResult
  func upload(
    _ request: Helpers.HTTPRequest,
    data: Data,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

    let response = try await http.upload(request, from: data, progress: progress)

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

  @discardableResult
  func upload(
    _ request: Helpers.HTTPRequest,
    fileURL: URL,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

    let response = try await http.upload(request, fromFile: fileURL, progress: progress)

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

  @discardableResult
  func download(
    _ request: Helpers.HTTPRequest,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> Data {
    var request = request
    request.headers = HTTPFields(configuration.headers).merging(with: request.headers)

    let downloadResponse = try await http.download(request, progress: progress)

    guard (200..<300).contains(downloadResponse.response.statusCode) else {
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: downloadResponse.data
      ) {
        throw error
      }

      throw HTTPError(data: downloadResponse.data, response: downloadResponse.response)
    }

    return downloadResponse.data
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
