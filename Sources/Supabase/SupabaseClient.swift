import _Helpers
@_exported import Auth
import ConcurrencyExtras
import Foundation
@_exported import Functions
@_exported import PostgREST
@_exported import Realtime
@_exported import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public typealias SupabaseLogger = _Helpers.SupabaseLogger
public typealias SupabaseLogLevel = _Helpers.SupabaseLogLevel
public typealias SupabaseLogMessage = _Helpers.SupabaseLogMessage

let version = _Helpers.version

/// Supabase Client.
public final class SupabaseClient: Sendable {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured
  /// by access policies.
  public let auth: AuthClient

  var rest: PostgrestClient {
    mutableState.withValue {
      if $0.rest == nil {
        $0.rest = PostgrestClient(
          url: databaseURL,
          schema: options.db.schema,
          headers: defaultHeaders.dictionary,
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
            headers: defaultHeaders.dictionary,
            session: StorageHTTPSession(fetch: fetchWithAuth, upload: uploadWithAuth),
            logger: options.global.logger
          )
        )
      }

      return $0.storage!
    }
  }

  let _realtime: UncheckedSendable<RealtimeClient>

  /// Realtime client for Supabase
  public let realtimeV2: RealtimeClientV2

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public var functions: FunctionsClient {
    mutableState.withValue {
      if $0.functions == nil {
        $0.functions = FunctionsClient(
          url: functionsURL,
          headers: defaultHeaders.dictionary,
          region: options.functions.region,
          logger: options.global.logger,
          fetch: fetchWithAuth
        )
      }

      return $0.functions!
    }
  }

  let defaultHeaders: HTTPHeaders

  struct MutableState {
    var listenForAuthEventsTask: Task<Void, Never>?
    var storage: SupabaseStorageClient?
    var rest: PostgrestClient?
    var functions: FunctionsClient?
  }

  private let mutableState = LockIsolated(MutableState())

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

    defaultHeaders = HTTPHeaders([
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "Apikey": supabaseKey,
    ])
    .merged(with: HTTPHeaders(options.global.headers))

    auth = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: defaultHeaders.dictionary,
      flowType: options.auth.flowType,
      redirectToURL: options.auth.redirectToURL,
      localStorage: options.auth.storage,
      logger: options.global.logger,
      encoder: options.auth.encoder,
      decoder: options.auth.decoder,
      fetch: {
        // DON'T use `fetchWithAuth` method within the AuthClient as it may cause a deadlock.
        try await options.global.session.data(for: $0)
      }
    )

    _realtime = UncheckedSendable(
      RealtimeClient(
        supabaseURL.appendingPathComponent("/realtime/v1").absoluteString,
        headers: defaultHeaders.dictionary,
        params: defaultHeaders.dictionary
      )
    )

    var realtimeOptions = options.realtime
    realtimeOptions.headers.merge(with: defaultHeaders)

    if realtimeOptions.logger == nil {
      realtimeOptions.logger = options.global.logger
    }

    realtimeV2 = RealtimeClientV2(
      url: supabaseURL.appendingPathComponent("/realtime/v1"),
      options: realtimeOptions
    )

    listenForAuthEvents()
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
  public var channels: [RealtimeChannelV2] {
    get async {
      await Array(realtimeV2.subscriptions.values)
    }
  }

  /// Creates a Realtime channel with Broadcast, Presence, and Postgres Changes.
  /// - Parameters:
  ///   - name: The name of the Realtime channel.
  ///   - options: The options to pass to the Realtime channel.
  public func channel(
    _ name: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) async -> RealtimeChannelV2 {
    await realtimeV2.channel(name, options: options)
  }

  /// Unsubscribes and removes Realtime channel from Realtime client.
  /// - Parameter channel: The Realtime channel to remove.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    await realtimeV2.removeChannel(channel)
  }

  /// Unsubscribes and removes all Realtime channels from Realtime client.
  public func removeAllChannels() async {
    await realtimeV2.removeAllChannels()
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
    var request = request
    if let accessToken = try? await auth.session.accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
    guard [
      .initialSession,
      .signedIn,
      .tokenRefreshed,
      .signedOut,
    ].contains(event) else { return }

    realtime.setAuth(session?.accessToken)
    await realtimeV2.setAuth(session?.accessToken)
  }
}
