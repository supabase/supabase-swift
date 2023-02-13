import Foundation
import Functions
import Get
import GoTrue
import PostgREST
import Realtime
import SupabaseStorage

/// Supabase Client.
public class SupabaseClient {
  private let supabaseURL: URL
  private let supabaseKey: String
  private let schema: String

  let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: GoTrueClient

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public var storage: SupabaseStorageClient {
    SupabaseStorageClient(
      url: supabaseURL.appendingPathComponent("/storage/v1").absoluteString,
      headers: defaultHeaders,
      http: self
    )
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    PostgrestClient(
      url: supabaseURL.appendingPathComponent("/rest/v1"),
      headers: defaultHeaders,
      schema: schema,
      apiClientDelegate: self
    )
  }

  /// Realtime client for Supabase
  public var realtime: RealtimeClient {
    RealtimeClient(
      endPoint: supabaseURL.appendingPathComponent("/realtime/v1").absoluteString,
      params: defaultHeaders
    )
  }

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public var functions: FunctionsClient {
    FunctionsClient(
      url: functionsURL,
      headers: defaultHeaders,
      apiClientDelegate: self
    )
  }

  private var defaultHeaders: [String: String]

  /// Init `Supabase` with the provided parameters.
  /// - Parameters:
  ///   - supabaseURL: Unique Supabase project url
  ///   - supabaseKey: Supabase anonymous API Key
  ///   - schema: Database schema name, defaults to `public`
  ///   - headers: Optional headers for initializing the client.
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    schema: String = "public",
    headers: [String: String] = [:],
    httpClient: HTTPClient = HTTPClient()
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    self.schema = schema
    self.httpClient = httpClient

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "apikey": supabaseKey,
    ].merging(headers) { _, new in new }

    auth = GoTrueClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: defaultHeaders
    )

    let isPlatform =
      supabaseURL.absoluteString.contains("supabase.co")
        || supabaseURL.absoluteString.contains("supabase.in")
    if isPlatform {
      let urlParts = supabaseURL.absoluteString.split(separator: ".")
      functionsURL = URL(string: "\(urlParts[0]).functions.\(urlParts[1]).\(urlParts[2])")!
    } else {
      functionsURL = supabaseURL.appendingPathComponent("functions/v1")
    }
  }

  public struct HTTPClient {
    let storage: StorageHTTPClient

    public init(
      storage: StorageHTTPClient? = nil
    ) {
      self.storage = storage ?? DefaultStorageHTTPClient()
    }
  }

  private let httpClient: HTTPClient
}

extension SupabaseClient: APIClientDelegate {
  public func client(_: APIClient, willSendRequest request: inout URLRequest) async throws {
    request = await adapt(request: request)
  }
}

extension SupabaseClient {
  func adapt(request: URLRequest) async -> URLRequest {
    var request = request
    if let accessToken = try? await auth.session.accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}

extension SupabaseClient: StorageHTTPClient {
  public func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let request = await adapt(request: request)
    return try await httpClient.storage.fetch(request)
  }

  public func upload(
    _ request: URLRequest,
    from data: Data
  ) async throws -> (Data, HTTPURLResponse) {
    let request = await adapt(request: request)
    return try await httpClient.storage.upload(request, from: data)
  }
}
