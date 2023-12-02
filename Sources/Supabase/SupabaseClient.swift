import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers
@_exported import Auth
@_exported import Functions
@_exported import PostgREST
@_exported import Realtime
@_exported import Storage

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let version = _Helpers.version

/// Supabase Client.
public final class SupabaseClient: @unchecked Sendable {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: AuthClient

  /// Database client for Supabase.
  public private(set) lazy var database = PostgrestClient(
    url: databaseURL,
    schema: options.db.schema,
    headers: defaultHeaders,
    fetch: fetchWithAuth,
    encoder: options.db.encoder,
    decoder: options.db.decoder
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
  public let realtime: RealtimeClient

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public private(set) lazy var functions = FunctionsClient(
    url: functionsURL,
    headers: defaultHeaders,
    fetch: fetchWithAuth
  )

  let defaultHeaders: [String: String]
  private let listenForAuthEventsTask = LockIsolated(Task<Void, Never>?.none)

  private var session: URLSession {
    options.global.session
  }

  /// Create a new client.
  /// - Parameters:
  ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in
  /// your project dashboard.
  ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in
  /// your project dashboard.
  ///   - options: Custom options to configure client's behavior.
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
    functionsURL = supabaseURL.appendingPathComponent("/functions/v1")

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "apikey": supabaseKey,
    ].merging(options.global.headers) { _, new in new }

    auth = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: defaultHeaders,
      flowType: options.auth.flowType,
      localStorage: options.auth.storage,
      encoder: options.auth.encoder,
      decoder: options.auth.decoder,
      fetch: {
        // DON'T use `fetchWithAuth` method within the AuthClient as it may cause a deadlock.
        try await options.global.session.data(for: $0)
      }
    )

    realtime = RealtimeClient(
      supabaseURL.appendingPathComponent("/realtime/v1").absoluteString,
      headers: defaultHeaders,
      params: defaultHeaders
    )

    listenForAuthEvents()
  }

  /// Create a new client.
  /// - Parameters:
  ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in
  /// your project dashboard.
  ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in
  /// your project dashboard.
  ///   - options: Custom options to configure client's behavior.
  public convenience init(
    supabaseURL: String,
    supabaseKey: String,
    options: SupabaseClientOptions = .init()
  ) {
    guard let supabaseURL = URL(string: supabaseURL) else {
      fatalError("Invalid supabaseURL: \(supabaseURL)")
    }

    self.init(supabaseURL: supabaseURL, supabaseKey: supabaseKey, options: options)
  }

  deinit {
    listenForAuthEventsTask.value?.cancel()
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
    listenForAuthEventsTask.setValue(
      Task {
        for await (event, session) in await auth.authStateChanges {
          handleTokenChanged(event: event, session: session)
        }
      }
    )
  }

  private func handleTokenChanged(event: AuthChangeEvent, session: Session?) {
    let supportedEvents: [AuthChangeEvent] = [.initialSession, .signedIn, .tokenRefreshed]
    guard supportedEvents.contains(event) else { return }

    realtime.setAuth(session?.accessToken)
  }
}
