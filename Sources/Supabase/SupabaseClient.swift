import ConcurrencyExtras
public import Foundation
import HTTPTypes
import Helpers
import IssueReporting
import Logging
@_spi(Experimental) import PostgREST
@_spi(Experimental) import Storage

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
/// - ``init(supabaseURL:supabaseKey:configuration:)``
/// - ``configuration``
/// - ``Configuration``
///
/// ### Supabase Services
/// - ``auth``
/// - ``storage``
/// - ``functions``
/// - ``realtime``
///
/// ### Querying the Database
/// - ``from(_:)->PostgrestQueryBuilder``
/// - ``rpc(_:params:count:)``
/// - ``rpc(_:count:)``
/// - ``schema(_:)->PostgrestClient``
///
/// ### Realtime Channels
/// - ``channels``
/// - ``channel(_:configure:)``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
///
/// ### Deep Links
/// - ``handleRedirect(_:)``
///
/// ### Configuration
/// - ``headers``
///
/// ## OpenTelemetry Trace Propagation
///
/// Enable the `OpenTelemetry` trait on your dependency declaration to have every outgoing
/// request automatically carry a W3C `traceparent` header derived from the currently active
/// OpenTelemetry span:
///
/// ```swift
/// .package(
///   url: "https://github.com/supabase/supabase-swift.git",
///   from: "2.0.0",
///   traits: ["OpenTelemetry"]
/// )
/// ```
///
/// No further configuration is needed — the trait is the only toggle. With it enabled, whatever
/// span is active (via `opentelemetry-swift`) when a request is made gets propagated; with no
/// active span, or with the trait disabled, requests go out unchanged.
public final class SupabaseClient: Sendable {
  /// Derives the default auth storage key from the project ref in `url`'s host, so two projects
  /// in the same app do not share a stored session.
  ///
  /// - Returns: `nil` when `url` has no host, and so no project ref to namespace by. An empty
  ///   host counts as none: `"".split(separator: ".")` is empty.
  static func defaultStorageKey(for url: URL) -> String? {
    url.host(percentEncoded: false)?
      .split(separator: ".").first
      .map { "sb-\($0)-auth-token" }
  }

  /// The configuration this client was created with.
  public let configuration: Configuration
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL
  var clock: any Clock<Duration> { configuration.global.clock }

  let _auth: AuthClient

  /// The Auth client for managing user sessions and authentication.
  ///
  /// Use this property to sign users in and out, retrieve the current session,
  /// and listen for authentication state changes.
  ///
  /// > Warning: Do not access this property when ``SupabaseClient/Configuration/Auth/accessToken``
  /// > is configured — the client will emit a runtime issue. Use a separate ``SupabaseClient``
  /// > without `accessToken` if you need both Supabase Auth and a third-party auth provider.
  public var auth: AuthClient {
    if configuration.auth.accessToken != nil {
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
    PostgrestClient(
      configuration: .init(
        url: databaseURL,
        schema: configuration.database.schema,
        headers: dataHeaders.dictionary,
        http: authenticatedHTTP(staleTokenRejection: .postgrest),
        logger: configuration.global.logger,
        encoder: configuration.database.encoder,
        decoder: configuration.database.decoder,
        retryEnabled: configuration.database.retry
      )
    )
  }

  /// The Storage client for uploading, downloading, and managing files.
  public var storage: StorageClient {
    var storageConfiguration = StorageClient.Configuration(
      url: storageURL,
      headers: dataHeaders,
      usesNewHostname: configuration.storage.usesNewHostname,
      http: authenticatedHTTP(staleTokenRejection: .storage),
      logger: configuration.global.logger,
      retryEnabled: configuration.storage.retryEnabled,
      clock: clock
    )
    storageConfiguration.resumable = configuration.storage.resumable
    return StorageClient(configuration: storageConfiguration)
  }

  /// The Realtime client for subscribing to database changes and broadcasting presence events.
  public var realtime: RealtimeClient {
    mutableState.withValue {
      if let realtime = $0.realtime {
        return realtime
      }
      let realtime = _initRealtimeClient()
      $0.realtime = realtime
      return realtime
    }
  }

  /// The Functions client for invoking Supabase Edge Functions.
  ///
  /// Built on first access from ``SupabaseClient/Configuration/Functions`` and the global HTTP
  /// configuration, then cached.
  public var functions: FunctionsClient {
    mutableState.withValue {
      if let functions = $0.functions {
        return functions
      }
      let functions = _initFunctionsClient()
      $0.functions = functions
      return functions
    }
  }

  /// ``_headers`` without the static `Authorization`, for PostgREST, Storage and Functions: their
  /// bearer is the bearer middleware's job, so a per-call header and the session token both win
  /// over the key.
  var dataHeaders: HTTPFields {
    var headers = _headers
    headers[.authorization] = nil
    return headers
  }

  let _headers: HTTPFields
  /// The HTTP headers included in every request made by sub-clients.
  ///
  /// This dictionary is read-only. To supply custom headers, set
  /// ``SupabaseClient/Configuration/Global/headers`` when initializing the client.
  public var headers: [String: String] {
    _headers.dictionary
  }

  struct MutableState {
    var listenForAuthEventsTask: Task<Void, Never>?
    var realtime: RealtimeClient?
    var functions: FunctionsClient?

    var changedAccessToken: String?
  }

  let mutableState = LockIsolated(MutableState())

  /// Creates a client.
  /// - Parameters:
  ///   - supabaseURL: Your Supabase project URL, found in the project dashboard.
  ///   - supabaseKey: Your Supabase project anon key, found in the project dashboard.
  ///   - configuration: Settings for the client and its sub-clients.
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    configuration: Configuration = .init()
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    self.configuration = configuration

    APIKeyFormat.checkFormat(supabaseKey)

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
      .merging(with: HTTPFields(configuration.global.headers))

    guard let defaultStorageKey = Self.defaultStorageKey(for: supabaseURL) else {
      preconditionFailure(
        """
        supabaseURL must have a host to derive the auth storage key from, got \(supabaseURL).
        """
      )
    }

    let authConfiguration = AuthClient.Configuration(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      storageKey: configuration.auth.storageKey ?? defaultStorageKey,
      headers: _headers,
      storage: configuration.auth.storage,
      redirectTo: configuration.auth.redirectToURL,
      autoRefresh: configuration.auth.accessToken == nil
        ? configuration.auth.autoRefresh : .disabled,
      observesAppLifecycle: configuration.auth.observesAppLifecycle,
      http: Self.resolveHTTP(
        global: configuration.global.http,
        override: configuration.auth.http,
        sdkMiddlewares: [TraceContextMiddleware()]
      ),
      logger: configuration.auth.logger ?? configuration.global.logger,
      clock: configuration.auth.clock ?? configuration.global.clock
    )
    _auth = AuthClient(configuration: authConfiguration)

    if configuration.auth.accessToken == nil {
      listenForAuthEvents()
    }
  }

  /// Creates a query builder targeting a table or view.
  /// - Parameter table: The name of the table or view to query.
  /// - Returns: A query builder for constructing and executing the query.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    rest.from(table)
  }

  /// Creates a typed source for a relation, queried in the schema the relation declares.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``_PostgrestSource`` for that relation.
  @_spi(Experimental)
  public func from<R: _PostgrestRelation>(_ relation: R.Type) -> _PostgrestSource<R> {
    rest.from(relation)
  }

  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func from<R: _PostgrestRelation>(_ relation: R.Type, _: Void = ()) -> _PostgrestSource<R> {
    fatalError()
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

  /// Calls a database function with typed arguments. See ``PostgrestClient/rpc(_:)``.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  @_spi(Experimental)
  public func rpc<F: _PostgrestFunction>(_ function: F) throws -> _PostgrestFunctionQuery<F.Result>
  {
    try rest.rpc(function)
  }

  // See the unavailable `from(_:_:)` twin: it names the missing SPI import.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func rpc<F: _PostgrestFunction>(_ function: F, _: Void = ()) throws
    -> _PostgrestFunctionQuery<F.Result>
  {
    fatalError()
  }

  /// The generated database function methods. See ``PostgrestClient/rpc``.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  @_spi(Experimental)
  public var rpc: _PostgrestFunctions { rest.rpc }

  /// Returns a database client scoped to the given Postgres schema.
  ///
  /// The schema must be on the list of exposed schemas in your Supabase project dashboard.
  /// - Parameter schema: The schema to query.
  /// - Returns: A ``PostgrestClient`` configured for the given schema.
  public func schema(_ schema: String) -> PostgrestClient {
    rest.schema(schema)
  }

  /// Returns a scope that only queries relations declared to live in the given schema.
  ///
  /// - Precondition: ``SupabaseClient/Configuration/Database/schema`` is not set.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameter schema: The schema type to query.
  /// - Returns: A ``_PostgrestSchemaScope`` for that schema.
  @_spi(Experimental)
  public func schema<S: _PostgrestSchema>(_ schema: S.Type) -> _PostgrestSchemaScope<S> {
    rest.schema(schema)
  }

  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func schema<S: _PostgrestSchema>(
    _ schema: S.Type, _: Void = ()
  ) -> _PostgrestSchemaScope<S> {
    fatalError()
  }

  /// All active Realtime channels.
  ///
  /// The Realtime client owns its channels, so the read is `async`.
  public var channels: [RealtimeChannel] {
    get async { await realtime.channels }
  }

  /// Returns the Realtime channel for `name`, creating it when it does not exist, with support
  /// for Broadcast, Presence, and Postgres Changes.
  ///
  /// `configure` runs on the caller's actor before the call reaches the Realtime client.
  ///
  /// ```swift
  /// let channel = await supabase.channel("room:lobby") { $0.broadcast.receiveOwnMessages = true }
  /// try await channel.subscribe()
  /// ```
  ///
  /// - Parameters:
  ///   - name: A unique name for the channel.
  ///   - configure: A closure that sets the channel's ``RealtimeChannelConfiguration``. A
  ///     channel that already exists for `name` keeps its configuration.
  /// - Returns: A configured ``RealtimeChannel`` ready to subscribe.
  public func channel(
    _ name: String,
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) async -> RealtimeChannel {
    await realtime.channel(name, configure: configure)
  }

  /// Unsubscribes from and removes a Realtime channel.
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannel) async {
    await realtime.removeChannel(channel)
  }

  /// Unsubscribes from and removes all active Realtime channels.
  public func removeAllChannels() async {
    await realtime.removeAllChannels()
  }

  /// Finishes the auth flow that a redirect URL reports. Forwards to
  /// ``AuthClient/handleRedirect(_:)``.
  ///
  /// Pass the URLs that reach your auth callback. ``AuthClient/isAuthRedirect(_:)`` checks one. A
  /// URL that is not an auth redirect returns `nil`: only a URL that opens
  /// ``SupabaseClient/Configuration/Auth/redirectToURL`` or the redirect URL of a pending flow is
  /// one. The same URL can arrive more than once; the later deliveries get the first result and
  /// send no request.
  ///
  /// A URL with tokens (`#access_token=…`) signs in the account that the tokens belong to. Pass
  /// only URLs that reach your own callback.
  ///
  /// ```swift
  /// SomeView()
  ///   .onOpenURL { url in
  ///     Task { try await supabase.handleRedirect(url) }
  ///   }
  /// ```
  ///
  /// - Parameter url: The URL that opened the app.
  /// - Returns: `nil` when `url` is not an auth redirect, else what the redirect did.
  @discardableResult
  public func handleRedirect(_ url: URL) async throws -> RedirectResult? {
    try await auth.handleRedirect(url)
  }

  deinit {
    mutableState.listenForAuthEventsTask?.cancel()
  }

  /// A module's HTTP configuration: `override` on top of `global`, field by field.
  ///
  /// A `nil` transport or timeout in `override` falls back to the global one, and the transport
  /// to ``URLSessionTransport`` when neither sets one. The middlewares run in this order: the
  /// global ones, the module's own, then the SDK's.
  private static func resolveHTTP(
    global: HTTPClientConfiguration,
    override: HTTPClientConfiguration?,
    sdkMiddlewares: [any ClientMiddleware]
  ) -> HTTPClientConfiguration {
    HTTPClientConfiguration(
      transport: override?.transport ?? global.transport ?? URLSessionTransport(),
      middlewares: global.middlewares + (override?.middlewares ?? []) + sdkMiddlewares,
      timeout: override?.timeout ?? global.timeout
    )
  }

  /// The resolved transport shared by every sub-client.
  private var transport: any ClientTransport {
    configuration.global.http.transport ?? URLSessionTransport()
  }

  /// The shared transport plus the user's middlewares followed by the SDK's, for PostgREST and
  /// Storage. The bearer is the session token, else the key.
  ///
  /// The bearer middleware captures only the dependencies it needs, never `self`, because each
  /// sub-client stores its middlewares for its whole lifetime: the cached ``realtime`` and
  /// ``functions`` sub-clients are held in ``mutableState`` for the lifetime of the client, and a
  /// caller may hold any sub-client for that long too. Capturing `self` here would form a
  /// `self -> sub-client -> middleware -> self` retain cycle that keeps ``deinit`` from ever
  /// running.
  private func authenticatedHTTP(
    staleTokenRejection: StaleTokenRejection
  ) -> HTTPClientConfiguration {
    HTTPClientConfiguration(
      transport: transport,
      middlewares: configuration.global.http.middlewares + [
        TraceContextMiddleware(),
        bearerMiddleware(staleTokenRejection: staleTokenRejection),
      ],
      timeout: configuration.global.http.timeout
    )
  }

  /// - Parameter bearerToken: Maps the token to the bearer to send, `nil` for none. It sees the
  ///   key and a third-party provider's token, not a session token.
  private func bearerMiddleware(
    staleTokenRejection: StaleTokenRejection,
    bearerToken: @escaping @Sendable (String) -> String? = { $0 }
  ) -> any ClientMiddleware {
    guard configuration.auth.accessToken == nil else {
      return AccessTokenMiddleware(getAccessToken: {
        [provider = accessTokenProvider, supabaseKey] in
        bearerToken(try await provider() ?? supabaseKey)
      })
    }
    return AuthMiddleware(
      auth: _auth,
      fallbackToken: bearerToken(supabaseKey),
      staleTokenRejection: staleTokenRejection,
      autoRefresh: configuration.auth.autoRefresh
    )
  }

  /// Resolves the access token to send on outgoing requests, without capturing `self`.
  ///
  /// Swallows only ``AuthError/sessionMissing`` — the expected "no signed-in user" case, which
  /// should resolve to `nil` (falling back to the anon key) rather than failing the caller. Every
  /// other error (a network failure refreshing the session, or one thrown by a configured
  /// ``SupabaseClient/Configuration/Auth/accessToken`` third-party auth provider) propagates, so
  /// callers of this closure never need their own knowledge of which auth errors are benign.
  private var accessTokenProvider: @Sendable () async throws -> String? {
    { [accessToken = configuration.auth.accessToken, auth = _auth] in
      do {
        if let accessToken {
          return try await accessToken()
        }
        return try await auth.session().accessToken
      } catch let error as AuthError where error.kind == .sessionMissing {
        return nil
      }
    }
  }

  private func _getAccessToken() async throws -> String? {
    try await accessTokenProvider()
  }

  /// Mirrors Auth state onto the Realtime V2 sub-client for the client's lifetime.
  ///
  /// `events()` finishes only when the Auth client is released, and this client owns it, so the
  /// observing task must not capture `self` strongly: it would keep the client alive forever, and
  /// ``deinit`` — the only place that cancels this task — could never run. The stream is
  /// therefore resolved up front (so the task doesn't need `self` to reach `auth`) and `self` is
  /// captured weakly.
  private func listenForAuthEvents() {
    let task = Task { [weak self, events = _auth.events()] in
      for await change in events {
        guard let self else { return }
        await self.handleTokenChanged(event: change.event, session: change.session)
      }
    }
    mutableState.withValue {
      $0.listenForAuthEventsTask = task
    }
  }

  /// Pushes the new token to the Realtime client only when it already exists. Building it here
  /// would install its observers in apps that never use Realtime; a client built later pulls
  /// the current token itself.
  func handleTokenChanged(event: AuthEvent, session: Session?) async {
    if let accessToken = realtimeTokenToPush(event: event, session: session),
      let realtime = mutableState.realtime
    {
      await realtime.setAuth(accessToken)
    }
  }

  /// The token Realtime has to receive for this change, or `nil` when it already has it.
  ///
  /// The token is derived from the session, not from the event kind: any event can carry a new
  /// one. A recovery or email-change verification, an MFA step-up, or a linked identity replaces
  /// the session without a `.signedIn`. A signed-out change resets Realtime to the API key.
  ///
  /// Calling it records the token as pushed, so call it once per change.
  func realtimeTokenToPush(event: AuthEvent, session: Session?) -> String? {
    mutableState.withValue {
      if event == .signedOut {
        $0.changedAccessToken = nil
        return supabaseKey
      }

      guard $0.changedAccessToken != session?.accessToken else { return nil }
      $0.changedAccessToken = session?.accessToken
      return session?.accessToken ?? supabaseKey
    }
  }

  private func _initFunctionsClient() -> FunctionsClient {
    FunctionsClient(
      configuration: .init(
        url: functionsURL,
        headers: dataHeaders,
        region: configuration.functions.region,
        http: Self.resolveHTTP(
          global: configuration.global.http,
          override: configuration.functions.http,
          sdkMiddlewares: [
            TraceContextMiddleware(),
            bearerMiddleware(staleTokenRejection: .functions) { [supabaseKey] in
              APIKeyFormat.functionsBearerToken(accessToken: $0, supabaseKey: supabaseKey)
            },
          ]
        ),
        logger: configuration.functions.logger ?? configuration.global.logger,
        decoder: configuration.functions.decoder
      )
    )
  }

  private func _initRealtimeClient() -> RealtimeClient {
    let realtime = configuration.realtime
    var http = realtime.http
    if http.transport == nil {
      http = HTTPClientConfiguration(
        transport: transport,
        middlewares: configuration.global.http.middlewares + realtime.http.middlewares
          + [TraceContextMiddleware()],
        timeout: realtime.http.timeout ?? configuration.global.http.timeout
      )
    }

    return RealtimeClient(
      configuration: .init(
        url: supabaseURL.appendingPathComponent("/realtime/v1"),
        // Through `HTTPFields`, so names compare without regard to case and the global headers
        // win.
        headers: HTTPFields(realtime.headers).merging(with: _headers).dictionary,
        heartbeatInterval: realtime.heartbeatInterval,
        requestTimeout: realtime.requestTimeout,
        connectOnSubscribe: realtime.connectOnSubscribe,
        disconnectOnEmptyChannelsAfter: realtime.disconnectOnEmptyChannelsAfter,
        handleAppLifecycle: realtime.handleAppLifecycle,
        monitorsNetworkPath: realtime.monitorsNetworkPath,
        serverLogLevel: realtime.serverLogLevel,
        accessToken: { [weak self] in try await self?._getAccessToken() },
        webSocketTransport: realtime.webSocketTransport,
        http: http,
        logger: realtime.logger ?? configuration.global.logger,
        clock: clock
      )
    )
  }
}
