import Foundation
@_exported import Functions
@_exported import GoTrue
@_exported import PostgREST
@_exported import Realtime
@_exported import Storage

/// Supabase Client.
public class SupabaseClient {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let realtimeURL: URL
  let authURL: URL
  let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public var auth: GoTrueClient {
    GoTrueClient(
      url: authURL,
      headers: defaultHeaders,
      localStorage: options.auth.storage,
      fetch: fetch
    )
  }

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public var storage: SupabaseStorageClient {
    SupabaseStorageClient(
      url: storageURL.absoluteString,
      headers: defaultHeaders,
      session: StorageHTTPSession(
        fetch: fetch,
        upload: upload
      )
    )
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    PostgrestClient(
      url: databaseURL,
      schema: options.db.schema,
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
  private var session: URLSession {
    options.global.session
  }

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
    self.options = options

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "apikey": supabaseKey,
    ].merging(options.global.headers) { _, new in new }
  }

  @Sendable
  private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: adapt(request: request))
  }

  @Sendable
  private func upload(
    _ request: URLRequest,
    from data: Data
  ) async throws -> (Data, URLResponse) {
    try await session.upload(for: adapt(request: request), from: data)
  }

  private func adapt(request: URLRequest) async -> URLRequest {
    var request = request
    if let accessToken = try? await auth.session.accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}
