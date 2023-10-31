import Foundation
@_spi(Internal) import _Helpers
@_exported import Functions
@_exported import GoTrue
@_exported import PostgREST
@_exported import Realtime
@_exported import Storage

let version = _Helpers.version

/// Supabase Client.
public class SupabaseClient {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let realtimeURL: URL
  let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: GoTrueClient

  /// Database client for Supabase.
  public private(set) lazy var database = PostgrestClient(
    url: databaseURL,
    schema: options.db.schema,
    headers: defaultHeaders,
    fetch: fetchWithAuth
  )

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public private(set) lazy var storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: storageURL,
      headers: defaultHeaders,
      session: StorageHTTPSession(fetch: fetchWithAuth, upload: uploadWithAuth)
    )
  )

  /// Realtime client for Supabase
  public private(set) lazy var realtime = RealtimeClient(
    realtimeURL.absoluteString,
    headers: defaultHeaders,
    params: defaultHeaders
  )

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public private(set) lazy var functions = FunctionsClient(
    url: functionsURL,
    headers: defaultHeaders,
    fetch: fetchWithAuth
  )

  private(set) var defaultHeaders: [String: String]
  private var listenForAuthEventsTask: Task<Void, Never>?

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
    self.options = options

    storageURL = supabaseURL.appendingPathComponent("/storage/v1")
    databaseURL = supabaseURL.appendingPathComponent("/rest/v1")
    realtimeURL = supabaseURL.appendingPathComponent("/realtime/v1")
    functionsURL = supabaseURL.appendingPathComponent("/functions/v1")

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "apikey": supabaseKey,
    ].merging(options.global.headers) { _, new in new }

    auth = GoTrueClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: defaultHeaders,
      flowType: options.auth.flowType,
      localStorage: options.auth.storage
    )

    listenForAuthEvents()
  }

  deinit {
    listenForAuthEventsTask?.cancel()
  }

  @Sendable
  private func fetchWithAuth(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: adapt(request: request))
  }

  @Sendable
  private func uploadWithAuth(
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

  private func listenForAuthEvents() {
    listenForAuthEventsTask = Task {
      for await event in await auth.onAuthStateChange() {
        let session = try? await auth.session
        handleTokenChanged(event: event, session: session)
      }
    }
  }

  private func handleTokenChanged(event: AuthChangeEvent, session: Session?) {
    let supportedEvents: [AuthChangeEvent] = [.signedIn, .tokenRefreshed]
    guard supportedEvents.contains(event) else { return }

    realtime.setAuth(session?.accessToken)
  }
}
