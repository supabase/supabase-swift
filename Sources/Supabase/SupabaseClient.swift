import ConcurrencyExtras
public import Foundation
import HTTPTypes
import IssueReporting

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// The unified client for all Supabase services.
///
/// Create one instance per Supabase project and share it across your app.
///
/// ```swift
/// let supabase = SupabaseClient(
///   supabaseURL: URL(string: "https://your-project.supabase.co")!,
///   supabaseKey: "your-anon-key"
/// )
/// ```
///
/// ## Topics
///
/// ### Creating a Client
/// - ``init(supabaseURL:supabaseKey:)``
/// - ``init(supabaseURL:supabaseKey:options:)``
///
/// ### Supabase Services
/// - ``auth``
/// - ``storage``
/// - ``functions``
/// - ``realtimeV2``
///
/// ### Querying the Database
/// - ``from(_:)``
/// - ``rpc(_:params:count:)``
/// - ``rpc(_:count:)``
/// - ``schema(_:)``
///
/// ### Realtime Channels
/// - ``channels``
/// - ``channel(_:options:)``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
///
/// ### Deep Links
/// - ``handle(_:)``
///
/// ### Configuration
/// - ``headers``
public final class SupabaseClient: Sendable {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL

  private let _auth: AuthClient

  /// The Auth client for managing user sessions and authentication.
  ///
  /// Use this property to sign users in and out, retrieve the current session,
  /// and listen for authentication state changes.
  ///
  /// > Warning: Do not access this property when ``SupabaseClientOptions/AuthOptions/accessToken``
  /// > is configured — the client will emit a runtime issue. Use a separate ``SupabaseClient``
  /// > without `accessToken` if you need both Supabase Auth and a third-party auth provider.
  public var auth: AuthClient {
    if options.auth.accessToken != nil {
      reportIssue(
        """
        Supabase Client is configured with the auth.accessToken option,
        accessing supabase.auth is not possible.
        """
      )
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

  /// The Storage client for uploading, downloading, and managing files.
  public var storage: SupabaseStorageClient {
    mutableState.withValue {
      if $0.storage == nil {
        $0.storage = SupabaseStorageClient(
          configuration: StorageClientConfiguration(
            url: storageURL,
            headers: headers,
            session: StorageHTTPSession(fetch: fetchWithAuth, upload: uploadWithAuth),
            logger: options.global.logger,
            useNewHostname: options.storage.useNewHostname
          )
        )
      }

      return $0.storage!
    }
  }

  let _realtime: UncheckedSendable<RealtimeClient>

  /// The Realtime client for subscribing to database changes and broadcasting presence events.
  public var realtimeV2: RealtimeClientV2 {
    mutableState.withValue {
      if $0.realtime == nil {
        $0.realtime = _initRealtimeClient()
      }
      return $0.realtime!
    }
  }

  /// The Functions client for invoking Supabase Edge Functions.
  public var functions: FunctionsClient {
    mutableState.withValue {
      if $0.functions == nil {
        $0.functions = FunctionsClient(
          url: functionsURL,
          headers: headers,
          region: options.functions.region,
          logger: options.global.logger,
          fetch: fetchWithAuth,
          decoder: options.functions.decoder
        )
      }

      return $0.functions!
    }
  }

  let _headers: HTTPFields
  /// The HTTP headers included in every request made by sub-clients.
  ///
  /// This dictionary is read-only. To supply custom headers, set
  /// ``SupabaseClientOptions/GlobalOptions/headers`` when initializing the client.
  public var headers: [String: String] {
    _headers.dictionary
  }

  struct MutableState {
    var listenForAuthEventsTask: Task<Void, Never>?
    var storage: SupabaseStorageClient?
    var rest: PostgrestClient?
    var functions: FunctionsClient?
    var realtime: RealtimeClientV2?

    var changedAccessToken: String?
  }

  let mutableState = LockIsolated(MutableState())

  private var session: URLSession {
    options.global.session
  }

  #if !os(Linux) && !os(Android)
    /// Creates a client with default options.
    /// - Parameters:
    ///   - supabaseURL: Your Supabase project URL, found in the project dashboard.
    ///   - supabaseKey: Your Supabase project anon key, found in the project dashboard.
    public convenience init(supabaseURL: URL, supabaseKey: String) {
      self.init(
        supabaseURL: supabaseURL,
        supabaseKey: supabaseKey,
        options: SupabaseClientOptions()
      )
    }
  #endif

  /// Creates a client with custom options.
  /// - Parameters:
  ///   - supabaseURL: Your Supabase project URL, found in the project dashboard.
  ///   - supabaseKey: Your Supabase project anon key, found in the project dashboard.
  ///   - options: Configuration options for the client and its sub-clients.
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

    _headers = HTTPFields(defaultHeaders)
      .merging(
        with: HTTPFields(
          [
            "Authorization": "Bearer \(supabaseKey)",
            "Apikey": supabaseKey,
          ]
        )
      )
      .merging(with: HTTPFields(options.global.headers))

    // default storage key uses the supabase project ref as a namespace
    guard let host = supabaseURL.host(percentEncoded: false) else {
      preconditionFailure("supabaseURL must have a valid host.")
    }
    let defaultStorageKey = "sb-\(host.split(separator: ".")[0])-auth-token"

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
        try await options.global.session.data(for: TraceContext.inject(into: $0))
      },
      autoRefreshToken: options.auth.autoRefreshToken,
      emitLocalSessionAsInitialSession: options.auth.emitLocalSessionAsInitialSession
    )

    _realtime = UncheckedSendable(
      RealtimeClient(
        supabaseURL.appendingPathComponent("/realtime/v1").absoluteString,
        headers: _headers.dictionary,
        params: _headers.dictionary
      )
    )

    if options.auth.accessToken == nil {
      listenForAuthEvents()
    }
  }

  /// Creates a query builder targeting a table or view.
  /// - Parameter table: The name of the table or view to query.
  /// - Returns: A query builder for constructing and executing the query.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    rest.from(table)
  }

  /// Calls a Postgres function.
  /// - Parameters:
  ///   - fn: The name of the function to call.
  ///   - params: The parameters to pass to the function.
  ///   - count: The count algorithm to apply to rows returned by set-returning functions.
  /// - Returns: A filter builder for further narrowing the result set.
  /// - Throws: If encoding `params` fails or the function call returns an error.
  public func rpc(
    _ fn: String,
    params: some Encodable,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rest.rpc(fn, params: params, count: count)
  }

  /// Calls a Postgres function with no parameters.
  /// - Parameters:
  ///   - fn: The name of the function to call.
  ///   - count: The count algorithm to apply to rows returned by set-returning functions.
  /// - Returns: A filter builder for further narrowing the result set.
  /// - Throws: If the function call returns an error.
  public func rpc(
    _ fn: String,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rest.rpc(fn, count: count)
  }

  /// Returns a database client scoped to the given Postgres schema.
  ///
  /// The schema must be on the list of exposed schemas in your Supabase project dashboard.
  /// - Parameter schema: The schema to query.
  /// - Returns: A ``PostgrestClient`` configured for the given schema.
  public func schema(_ schema: String) -> PostgrestClient {
    rest.schema(schema)
  }

  /// All active Realtime channels.
  public var channels: [RealtimeChannelV2] {
    Array(realtimeV2.subscriptions.values)
  }

  /// Creates a Realtime channel with support for Broadcast, Presence, and Postgres Changes.
  /// - Parameters:
  ///   - name: A unique name for the channel.
  ///   - options: A closure to configure broadcast, presence, and Postgres change options.
  /// - Returns: A configured ``RealtimeChannelV2`` ready to subscribe.
  public func channel(
    _ name: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannelV2 {
    realtimeV2.channel(name, options: options)
  }

  /// Unsubscribes from and removes a Realtime channel.
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    await realtimeV2.removeChannel(channel)
  }

  /// Unsubscribes from and removes all active Realtime channels.
  public func removeAllChannels() async {
    await realtimeV2.removeAllChannels()
  }

  /// Passes an incoming URL to the Auth client for processing deep links and OAuth callbacks.
  ///
  /// Call this from your app's URL-handling entry points so Auth can complete OAuth and
  /// magic-link flows.
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
    let token = try? await _getAccessToken()

    var request = TraceContext.inject(into: request)
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func _getAccessToken() async throws -> String? {
    if let accessToken = options.auth.accessToken {
      try await accessToken()
    } else {
      try await auth.session.accessToken
    }
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
      if [.initialSession, .signedIn, .tokenRefreshed].contains(event),
        $0.changedAccessToken != session?.accessToken
      {
        $0.changedAccessToken = session?.accessToken
        return session?.accessToken ?? supabaseKey
      }

      if event == .signedOut {
        $0.changedAccessToken = nil
        return supabaseKey
      }

      return nil
    }

    if let accessToken {
      functions.setAuth(token: accessToken)
      realtime.setAuth(accessToken)
      await realtimeV2.setAuth(accessToken)
    }
  }

  private func _initRealtimeClient() -> RealtimeClientV2 {
    var realtimeOptions = options.realtime
    realtimeOptions.headers.merge(with: _headers)

    if realtimeOptions.logger == nil {
      realtimeOptions.logger = options.global.logger
    }

    if realtimeOptions.fetch == nil {
      realtimeOptions.fetch = { [session = options.global.session] request in
        try await session.data(for: TraceContext.inject(into: request))
      }
    }

    if realtimeOptions.accessToken == nil {
      realtimeOptions.accessToken = { [weak self] in
        try await self?._getAccessToken()
      }
    } else {
      reportIssue(
        """
        You assigned a custom `accessToken` closure to the RealtimeClientV2. This might not work as you expect
        as SupabaseClient uses Auth for pulling an access token to send on the realtime channels.

        Please make sure you know what you're doing.
        """
      )
    }

    return RealtimeClientV2(
      url: supabaseURL.appendingPathComponent("/realtime/v1"),
      options: realtimeOptions
    )
  }
}
