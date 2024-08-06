@_exported import Auth
import ConcurrencyExtras
import Foundation
@_exported import Functions
import Helpers
import IssueReporting
@_exported import PostgREST
@_exported import Realtime
@_exported import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public typealias SupabaseLogger = Helpers.SupabaseLogger
public typealias SupabaseLogLevel = Helpers.SupabaseLogLevel
public typealias SupabaseLogMessage = Helpers.SupabaseLogMessage

let version = Helpers.version

/// Supabase Client.
public final class SupabaseClient: Sendable {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL

  private let _auth: AuthClient

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured by access policies.
  public var auth: AuthClient {
    if options.auth.accessToken != nil {
      reportIssue("""
      Supabase Client is configured with the auth.accessToken option,
      accessing supabase.auth is not possible.
      """)
    }
    return _auth
  }

  var rest: PostgrestClient {
    mutableState.withValue {
      if $0.rest == nil {
        $0.rest = PostgrestClient(
          url: databaseURL,
          schema: options.db.schema,
          headers: headers,
          logger: options.global.logger,
          fetch: fetchWithAuth,
          encoder: options.db.encoder,
          decoder: options.db.decoder
        )
      }

      return $0.rest!
    }
  }

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public var storage: SupabaseStorageClient {
    mutableState.withValue {
      if $0.storage == nil {
        $0.storage = SupabaseStorageClient(
          configuration: StorageClientConfiguration(
            url: storageURL,
            headers: headers,
            session: StorageHTTPSession(fetch: fetchWithAuth, upload: uploadWithAuth),
            logger: options.global.logger
          )
        )
      }

      return $0.storage!
    }
  }

  /// Realtime client for Supabase
  public let realtime: RealtimeClient

  @available(*, deprecated, renamed: "realtime")
  public var realtimeV2: RealtimeClient { realtime }

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public var functions: FunctionsClient {
    mutableState.withValue {
      if $0.functions == nil {
        $0.functions = FunctionsClient(
          url: functionsURL,
          headers: headers,
          region: options.functions.region,
          logger: options.global.logger,
          fetch: fetchWithAuth
        )
      }

      return $0.functions!
    }
  }

  let _headers: HTTPHeaders
  /// Headers provided to the inner clients on initialization.
  ///
  /// - Note: This collection is non-mutable, if you want to provide different headers, pass it in ``SupabaseClientOptions/GlobalOptions/headers``.
  public var headers: [String: String] {
    _headers.dictionary
  }

  struct MutableState {
    var listenForAuthEventsTask: Task<Void, Never>?
    var storage: SupabaseStorageClient?
    var rest: PostgrestClient?
    var functions: FunctionsClient?

    var changedAccessToken: String?
  }

  let mutableState = LockIsolated(MutableState())

  private var session: URLSession {
    options.global.session
  }

  #if !os(Linux)
    /// Create a new client.
    /// - Parameters:
    ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in your project dashboard.
    ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in your project dashboard.
    public convenience init(supabaseURL: URL, supabaseKey: String) {
      self.init(
        supabaseURL: supabaseURL,
        supabaseKey: supabaseKey,
        options: SupabaseClientOptions()
      )
    }
  #endif

  /// Create a new client.
  /// - Parameters:
  ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in your project dashboard.
  ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in your project dashboard.
  ///   - options: Custom options to configure client's behavior.
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    options: SupabaseClientOptions
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    self.options = options

    storageURL = supabaseURL.appendingPathComponent("/storage/v1")
    databaseURL = supabaseURL.appendingPathComponent("/rest/v1")
    functionsURL = supabaseURL.appendingPathComponent("/functions/v1")

    _headers = HTTPHeaders([
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "Apikey": supabaseKey,
    ])
    .merged(with: HTTPHeaders(options.global.headers))

    // default storage key uses the supabase project ref as a namespace
    let defaultStorageKey = "sb-\(supabaseURL.host!.split(separator: ".")[0])-auth-token"

    _auth = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: _headers.dictionary,
      flowType: options.auth.flowType,
      redirectToURL: options.auth.redirectToURL,
      storageKey: options.auth.storageKey ?? defaultStorageKey,
      localStorage: options.auth.storage,
      logger: options.global.logger,
      encoder: options.auth.encoder,
      decoder: options.auth.decoder,
      fetch: {
        // DON'T use `fetchWithAuth` method within the AuthClient as it may cause a deadlock.
        try await options.global.session.data(for: $0)
      },
      autoRefreshToken: options.auth.autoRefreshToken
    )

    var realtimeOptions = options.realtime
    realtimeOptions.headers.merge(with: _headers)

    if realtimeOptions.logger == nil {
      realtimeOptions.logger = options.global.logger
    }

    realtime = RealtimeClient(
      url: supabaseURL.appendingPathComponent("/realtime/v1"),
      options: realtimeOptions
    )

    if options.auth.accessToken == nil {
      listenForAuthEvents()
    }
  }

  /// Performs a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  /// - Returns: A PostgrestQueryBuilder instance.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    rest.from(table)
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - params: The parameters to pass to the function call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///             Only applicable for set-returning functions.
  /// - Returns: A PostgrestFilterBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    _ fn: String,
    params: some Encodable & Sendable,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rest.rpc(fn, params: params, count: count)
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///            Only applicable for set-returning functions.
  /// - Returns: A PostgrestFilterBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    _ fn: String,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rest.rpc(fn, count: count)
  }

  /// Select a schema to query or perform an function (rpc) call.
  ///
  /// The schema needs to be on the list of exposed schemas inside Supabase.
  /// - Parameter schema: The schema to query.
  public func schema(_ schema: String) -> PostgrestClient {
    rest.schema(schema)
  }

  /// Returns all Realtime channels.
  public var channels: [RealtimeChannel] {
    get async { await Array(realtime.subscriptions.values) }
  }

  /// Creates a Realtime channel with Broadcast, Presence, and Postgres Changes.
  /// - Parameters:
  ///   - name: The name of the Realtime channel.
  ///   - options: The options to pass to the Realtime channel.
  public func channel(
    _ name: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) async -> RealtimeChannel {
    await realtime.channel(name, options: options)
  }

  /// Unsubscribes and removes Realtime channel from Realtime client.
  /// - Parameter channel: The Realtime channel to remove.
  public func removeChannel(_ channel: RealtimeChannel) async {
    await realtime.removeChannel(channel)
  }

  /// Unsubscribes and removes all Realtime channels from Realtime client.
  public func removeAllChannels() async {
    await realtime.removeAllChannels()
  }

  /// Handles an incoming URL received by the app.
  ///
  /// ## Usage example:
  ///
  /// ### UIKit app lifecycle
  ///
  /// In your `AppDelegate.swift`:
  ///
  /// ```swift
  /// public func application(
  ///   _ application: UIApplication,
  ///   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  /// ) -> Bool {
  ///   if let url = launchOptions?[.url] as? URL {
  ///     supabase.handle(url)
  ///   }
  ///
  ///   return true
  /// }
  ///
  /// func application(
  ///   _ app: UIApplication,
  ///   open url: URL,
  ///   options: [UIApplication.OpenURLOptionsKey: Any]
  /// ) -> Bool {
  ///   supabase.handle(url)
  ///   return true
  /// }
  /// ```
  ///
  /// ### UIKit app lifecycle with scenes
  ///
  /// In your `SceneDelegate.swift`:
  ///
  /// ```swift
  /// func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
  ///   guard let url = URLContexts.first?.url else { return }
  ///   supabase.handle(url)
  /// }
  /// ```
  ///
  /// ### SwiftUI app lifecycle
  ///
  /// In your `AppDelegate.swift`:
  ///
  /// ```swift
  /// SomeView()
  ///   .onOpenURL { url in
  ///     supabase.handle(url)
  ///   }
  /// ```
  public func handle(_ url: URL) {
    auth.handle(url)
  }

  deinit {
    mutableState.listenForAuthEventsTask?.cancel()
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
    let token: String? = if let accessToken = options.auth.accessToken {
      try? await accessToken()
    } else {
      try? await auth.session.accessToken
    }

    var request = request
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func listenForAuthEvents() {
    let task = Task {
      for await (event, session) in auth.authStateChanges {
        await handleTokenChanged(event: event, session: session)
      }
    }
    mutableState.withValue {
      $0.listenForAuthEventsTask = task
    }
  }

  private func handleTokenChanged(event: AuthChangeEvent, session: Session?) async {
    let accessToken: String? = mutableState.withValue {
      if [.initialSession, .signedIn, .tokenRefreshed].contains(event), $0.changedAccessToken != session?.accessToken {
        $0.changedAccessToken = session?.accessToken
        return session?.accessToken ?? supabaseKey
      }

      if event == .signedOut {
        $0.changedAccessToken = nil
        return supabaseKey
      }

      return nil
    }

    await realtime.setAuth(accessToken)
  }
}
