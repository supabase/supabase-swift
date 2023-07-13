import Foundation
@_exported import Functions
import Get
@_exported import GoTrue
@_exported import PostgREST
@_exported import Realtime
@_exported import SupabaseStorage

/// Supabase Client.
public class SupabaseClient {
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let realtimeURL: URL
  let authURL: URL
  let functionsURL: URL

  let schema: String

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: GoTrueClient

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public var storage: SupabaseStorageClient {
    SupabaseStorageClient(
      url: storageURL.absoluteString,
      headers: defaultHeaders,
      http: self
    )
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    PostgrestClient(
      url: databaseURL,
      schema: schema,
      headers: defaultHeaders,
      fetch: fetch
    )
  }

  /// Realtime client for Supabase
  public var realtime: RealtimeClient {
    RealtimeClient(
      endPoint: realtimeURL.absoluteString,
      params: defaultHeaders
    )
  }

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public var functions: FunctionsClient {
    FunctionsClient(
      url: functionsURL,
      headers: defaultHeaders,
      fetch: fetch
    )
  }

  private(set) var defaultHeaders: [String: String]

  /// Create a new client.
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    options: SupabaseClientOptions = .init()
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    authURL = supabaseURL.appendingPathComponent("/auth/v1")
    storageURL = supabaseURL.appendingPathComponent("/storage/v1")
    databaseURL = supabaseURL.appendingPathComponent("/rest/v1")
    realtimeURL = supabaseURL.appendingPathComponent("/realtime/v1")
    functionsURL = supabaseURL.appendingPathComponent("/functions/v1")

    schema = options.db.schema
    httpClient = options.global.httpClient

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "apikey": supabaseKey,
    ].merging(options.global.headers) { _, new in new }

    auth = GoTrueClient(
      url: authURL,
      headers: defaultHeaders,
      localStorage: options.auth.storage
    )
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

  @Sendable
  private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: adapt(request: request))
  }
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
