import Foundation
import Functions
import GoTrue
import PostgREST
import Realtime
import SupabaseStorage

/// Supabase Client.
public class SupabaseClient {
  private let supabaseURL: URL
  private let supabaseKey: String
  private let schema: String
  private let restURL: URL
  private let realtimeURL: URL
  private let authURL: URL
  private let storageURL: URL
  private let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: GoTrueClient

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public var storage: SupabaseStorageClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return SupabaseStorageClient(url: storageURL.absoluteString, headers: headers, http: self)
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return PostgrestClient(
      url: restURL.absoluteString,
      headers: headers,
      schema: schema,
      http: self
    )
  }

  /// Realtime client for Supabase
  public var realtime: RealtimeClient

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public var functions: FunctionsClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return FunctionsClient(
      url: functionsURL,
      headers: headers,
      http: self
    )
  }

  private var defaultHeaders: [String: String]

  /// Init `Supabase` with the provided parameters.
  /// - Parameters:
  ///   - supabaseURL: Unique Supabase project url
  ///   - supabaseKey: Supabase anonymous API Key
  ///   - schema: Database schema name, defaults to `public`
  ///   - autoRefreshToken: Toggles whether `Supabase.auth` automatically refreshes auth tokens.
  /// Defaults to `true`
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    schema: String = "public",
    httpClient: HTTPClient = HTTPClient()
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    self.schema = schema
    self.httpClient = httpClient
    restURL = supabaseURL.appendingPathComponent("/rest/v1")
    realtimeURL = supabaseURL.appendingPathComponent("/realtime/v1")
    authURL = supabaseURL.appendingPathComponent("/auth/v1")
    storageURL = supabaseURL.appendingPathComponent("/storage/v1")
    functionsURL = supabaseURL.appendingPathComponent("/functions/v1")

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "apikey": supabaseKey,
    ]

    auth = GoTrueClient(
      url: authURL,
      headers: defaultHeaders
    )
    realtime = RealtimeClient(endPoint: realtimeURL.absoluteString, params: defaultHeaders)
  }

  public struct HTTPClient {
    let storage: StorageHTTPClient
    let postgrest: PostgrestHTTPClient
    let functions: FunctionsHTTPClient

    public init(
      storage: StorageHTTPClient? = nil,
      postgrest: PostgrestHTTPClient? = nil,
      functions: FunctionsHTTPClient? = nil
    ) {
      self.storage = storage ?? DefaultStorageHTTPClient()
      self.postgrest = postgrest ?? DefaultPostgrestHTTPClient()
      self.functions = functions ?? DefaultFunctionsHTTPClient()
    }
  }

  private let httpClient: HTTPClient
}

extension SupabaseClient {
  func adapt(request: URLRequest) async throws -> URLRequest {
    try? await auth.refreshCurrentSessionIfNeeded()

    var request = request
    if let accessToken = auth.session?.accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}

extension SupabaseClient: PostgrestHTTPClient {
  public func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let request = try await adapt(request: request)
    return try await httpClient.postgrest.execute(request)
  }
}

extension SupabaseClient: StorageHTTPClient {
  public func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let request = try await adapt(request: request)
    return try await httpClient.storage.fetch(request)
  }

  public func upload(
    _ request: URLRequest,
    from data: Data
  ) async throws -> (Data, HTTPURLResponse) {
    let request = try await adapt(request: request)
    return try await httpClient.storage.upload(request, from: data)
  }
}

extension SupabaseClient: FunctionsHTTPClient {
  public func execute(
    _ request: URLRequest,
    client: FunctionsClient
  ) async throws -> (Data, HTTPURLResponse) {
    let request = try await adapt(request: request)
    return try await httpClient.functions.execute(request, client: client)
  }
}
