import ConcurrencyExtras
public import Foundation
import HTTPTypes
import Helpers
import IssueReporting
import Logging

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
/// - ``realtime``
///
/// ### Realtime Channels
/// - ``channel(_:configure:)``
/// - ``channels``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
///
/// ### Querying the Database
/// - ``from(_:)->PostgrestQueryBuilder``
/// - ``from(_:)->PostgrestSource<R>``
/// - ``rpc(_:params:count:)``
/// - ``rpc(_:count:)``
/// - ``schema(_:)->PostgrestClient``
/// - ``schema(_:)->PostgrestSchemaScope<S>``
///
/// ### Deep Links
/// - ``handle(_:)``
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

  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL
  let clock: any Clock<Duration>

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
    PostgrestClient(
      url: databaseURL,
      schema: options.db.schema,
      headers: dataHeaders.dictionary,
      logger: options.global.logger,
      http: authenticatedHTTP,
      encoder: options.db.encoder,
      decoder: options.db.decoder,
      retryEnabled: options.db.retry
    )
  }

  /// The Storage client for uploading, downloading, and managing files.
  public var storage: SupabaseStorageClient {
    var configuration = StorageClientConfiguration(
      url: storageURL,
      headers: dataHeaders.dictionary,
      http: authenticatedHTTP,
      logger: options.global.logger,
      usesNewHostname: options.storage.usesNewHostname,
      retryEnabled: options.storage.retryEnabled
    )
    configuration.clock = clock
    return SupabaseStorageClient(configuration: configuration)
  }

  /// The Functions client for invoking Supabase Edge Functions.
  ///
  /// Built on first access from ``SupabaseClientOptions/FunctionsOptions`` and the global HTTP
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
  /// bearer is ``AccessTokenMiddleware``'s job, so a per-call header and the session token both
  /// win over the key.
  var dataHeaders: HTTPFields {
    var headers = _headers
    headers[.authorization] = nil
    return headers
  }

  let _headers: HTTPFields
  /// The HTTP headers included in every request made by sub-clients.
  ///
  /// This dictionary is read-only. To supply custom headers, set
  /// ``SupabaseClientOptions/GlobalOptions/headers`` when initializing the client.
  public var headers: [String: String] {
    _headers.dictionary
  }

  /// The Realtime client, made on first access and then cached.
  ///
  /// It joins channels with the signed-in user's token, or the anon key when no one is signed
  /// in, and gets each new token when Auth signs in, refreshes or signs out.
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

  struct MutableState {
    var functions: FunctionsClient?
    var realtime: RealtimeClient?
    var authEventsTask: Task<Void, Never>?
  }

  let mutableState = LockIsolated(MutableState())

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
    self.clock = options.global.clock

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
      .merging(with: HTTPFields(options.global.headers))

    // The default storage key namespaces the stored session by project ref, taken from the URL's
    // host. `supabaseURL` is supplied once, at construction, so a URL without a host is a
    // programmer error rather than a runtime condition — trap on it, where the offending value is,
    // instead of degrading into a shared storage key that silently collides across projects.
    guard let defaultStorageKey = Self.defaultStorageKey(for: supabaseURL) else {
      preconditionFailure(
        """
        supabaseURL must have a host to derive the auth storage key from, got \(supabaseURL).
        """
      )
    }

    _auth = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: _headers.dictionary,
      flowType: options.auth.flowType,
      redirectToURL: options.auth.redirectToURL,
      storageKey: options.auth.storageKey ?? defaultStorageKey,
      localStorage: options.auth.storage,
      logger: options.global.logger,
      // DON'T give the AuthClient `AccessTokenMiddleware` — resolving the access token goes
      // through the AuthClient itself, which may cause a deadlock.
      http: HTTPClientConfiguration(
        transport: options.global.http.transport ?? URLSessionTransport(),
        middlewares: options.global.http.middlewares + [TraceContextMiddleware()],
        timeout: options.global.http.timeout
      ),
      automaticallyRefreshesToken: options.auth.automaticallyRefreshesToken,
      clock: clock
    )

    if options.auth.accessToken == nil {
      listenForAuthEvents()
    }
  }

  deinit {
    mutableState.authEventsTask?.cancel()
  }

  /// Creates a query builder targeting a table or view.
  /// - Parameter table: The name of the table or view to query.
  /// - Returns: A query builder for constructing and executing the query.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    rest.from(table)
  }

  /// Creates a typed source for a relation, queried in the schema the relation declares.
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``PostgrestSource`` for that relation.
  public func from<R: PostgrestRelation>(_ relation: R.Type) -> PostgrestSource<R> {
    rest.from(relation)
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

  /// Returns a scope that only queries relations declared to live in the given schema.
  ///
  /// - Precondition: ``SupabaseClientOptions/DatabaseOptions/schema`` is not set.
  /// - Parameter schema: The schema type to query.
  /// - Returns: A ``PostgrestSchemaScope`` for that schema.
  public func schema<S: PostgrestSchema>(_ schema: S.Type) -> PostgrestSchemaScope<S> {
    rest.schema(schema)
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

  /// Every channel on ``realtime``, sorted by topic. Empty, without making the Realtime client,
  /// until ``realtime`` is first used.
  public var channels: [RealtimeChannel] {
    mutableState.realtime?.channels ?? []
  }

  /// The Realtime channel for `topic`, made on the first call. Later calls return the same
  /// instance.
  ///
  /// - Parameters:
  ///   - topic: The channel name, without the `realtime:` prefix.
  ///   - configure: Sets the channel's options on a new channel.
  public func channel(
    _ topic: String,
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) -> RealtimeChannel {
    realtime.channel(topic, configure: configure)
  }

  /// Leaves `channel` and removes it from ``realtime``. Its streams finish.
  public func removeChannel(_ channel: RealtimeChannel) async {
    await realtime.removeChannel(channel)
  }

  /// Leaves and removes every Realtime channel. Does nothing, without making the Realtime client,
  /// until ``realtime`` is first used.
  public func removeAllChannels() async {
    await mutableState.realtime?.removeAllChannels()
  }

  /// The resolved transport shared by every sub-client.
  private var transport: any ClientTransport {
    options.global.http.transport ?? URLSessionTransport()
  }

  /// The shared transport plus the user's middlewares followed by the SDK's, for PostgREST and
  /// Storage. The bearer is the session token, else the key.
  ///
  /// ``AccessTokenMiddleware`` captures only the dependencies it needs — never `self` — because
  /// each sub-client stores its middlewares for its whole lifetime: the cached
  /// ``functions`` sub-client is held in ``mutableState`` for the lifetime of the client, and a
  /// caller may hold any sub-client for that long too. Capturing `self` here would form a
  /// `self -> sub-client -> middleware -> self` retain cycle that keeps `deinit` from ever
  /// running.
  private var authenticatedHTTP: HTTPClientConfiguration {
    HTTPClientConfiguration(
      transport: transport,
      middlewares: options.global.http.middlewares + [
        TraceContextMiddleware(),
        AccessTokenMiddleware(getAccessToken: { [provider = accessTokenProvider, supabaseKey] in
          try await provider() ?? supabaseKey
        }),
      ],
      timeout: options.global.http.timeout
    )
  }

  /// Resolves the access token to send on outgoing requests, without capturing `self`.
  ///
  /// Swallows only ``AuthError/sessionMissing`` — the expected "no signed-in user" case, which
  /// should resolve to `nil` (falling back to the anon key) rather than failing the caller. Every
  /// other error (a network failure refreshing the session, or one thrown by a configured
  /// ``SupabaseClientOptions/AuthOptions/accessToken`` third-party auth provider) propagates, so
  /// callers of this closure never need their own knowledge of which auth errors are benign.
  private var accessTokenProvider: @Sendable () async throws -> String? {
    { [accessToken = options.auth.accessToken, auth = _auth] in
      do {
        if let accessToken {
          return try await accessToken()
        }
        return try await auth.session.accessToken
      } catch let error as AuthError where error.kind == .sessionMissing {
        return nil
      }
    }
  }

  /// Sends Auth's token to ``realtime`` for the client's lifetime.
  ///
  /// `authStateChanges` never finishes, so the task holds `self` weakly: a strong capture would
  /// keep the client alive and ``deinit``, which cancels the task, would never run.
  private func listenForAuthEvents() {
    let task = Task { [weak self, authStateChanges = _auth.authStateChanges] in
      for await (event, session) in authStateChanges {
        guard let self else { return }
        await self.handleAuthEvent(event, session: session)
      }
    }
    mutableState.withValue { $0.authEventsTask = task }
  }

  /// Sends the session token, or the anon key without a session, to ``realtime`` on every
  /// event; an unchanged token is not sent again. Does nothing until ``realtime`` exists: a new
  /// client asks the provider for the token when it connects.
  private func handleAuthEvent(_ event: AuthChangeEvent, session: Session?) async {
    guard let realtime = mutableState.realtime else { return }
    await realtime.setAuth(session?.accessToken ?? supabaseKey)
  }

  private func _initRealtimeClient() -> RealtimeClient {
    var realtimeOptions = options.realtime
    realtimeOptions.headers = _headers.merging(with: options.realtime.headers)

    if realtimeOptions.customLogger == nil {
      realtimeOptions.logger = options.global.logger
      realtimeOptions.logger[metadataKey: "system"] = "realtime"
    }

    if realtimeOptions.http.transport == nil {
      realtimeOptions.http = HTTPClientConfiguration(
        transport: transport,
        middlewares: options.global.http.middlewares + realtimeOptions.http.middlewares
          + [TraceContextMiddleware()],
        timeout: realtimeOptions.http.timeout ?? options.global.http.timeout
      )
    }

    if realtimeOptions.accessToken == nil {
      realtimeOptions.accessToken = { [provider = accessTokenProvider, supabaseKey] in
        try await provider() ?? supabaseKey
      }
    } else {
      reportIssue(
        """
        options.realtime.accessToken is set. SupabaseClient gives Realtime the Auth session \
        token itself; a custom provider can join channels with a different token than the \
        one the rest of the client uses.
        """
      )
    }

    realtimeOptions.clock = clock

    return RealtimeClient(
      url: supabaseURL.appendingPathComponent("/realtime/v1"),
      options: realtimeOptions
    )
  }

  private func _initFunctionsClient() -> FunctionsClient {
    let http = options.functions.http ?? options.global.http
    return FunctionsClient(
      configuration: .init(
        url: functionsURL,
        headers: dataHeaders,
        region: options.functions.region,
        http: HTTPClientConfiguration(
          transport: http.transport ?? transport,
          middlewares: options.global.http.middlewares
            + (options.functions.http?.middlewares ?? [])
            + [
              TraceContextMiddleware(),
              // The session token, else the legacy JWT key; a new-format key is never a bearer.
              AccessTokenMiddleware(getAccessToken: {
                [provider = accessTokenProvider, supabaseKey] in
                APIKeyFormat.functionsBearerToken(
                  accessToken: try await provider() ?? supabaseKey, supabaseKey: supabaseKey)
              }),
            ],
          timeout: http.timeout ?? options.global.http.timeout
        ),
        logger: options.functions.logger ?? options.global.logger,
        decoder: options.functions.decoder
      )
    )
  }
}
