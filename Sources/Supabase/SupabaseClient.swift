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
  @available(
    *,
    deprecated,
    message: "Direct access to database is deprecated, please use one of the available methods such as, SupabaseClient.from(_:), SupabaseClient.rpc(_:params:), or SupabaseClient.schema(_:)."
  )
  public var database: PostgrestClient {
    rest
  }

  private lazy var rest = PostgrestClient(
    url: databaseURL,
    schema: options.db.schema,
    headers: defaultHeaders,
    logger: options.global.logger,
    fetch: fetchWithAuth,
    encoder: options.db.encoder,
    decoder: options.db.decoder
  )

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  public private(set) lazy var storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: storageURL,
      headers: defaultHeaders,
      session: StorageHTTPSession(fetch: fetchWithAuth, upload: uploadWithAuth),
      logger: options.global.logger
    )
  )

  /// Realtime client for Supabase
  public let realtime: RealtimeClient

  /// Realtime client for Supabase
  public let realtimeV2: RealtimeClientV2

  /// Supabase Functions allows you to deploy and invoke edge functions.
  public private(set) lazy var functions = FunctionsClient(
    url: functionsURL,
    headers: defaultHeaders,
    region: options.functions.region,
    logger: options.global.logger,
    fetch: fetchWithAuth
  )

  let defaultHeaders: [String: String]
  private let listenForAuthEventsTask = LockIsolated(Task<Void, Never>?.none)

  private var session: URLSession {
    options.global.session
  }

  #if !os(Linux)
    /// Create a new client.
    /// - Parameters:
    ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in
    /// your project dashboard.
    ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in
    /// your project dashboard.
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
  ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in
  /// your project dashboard.
  ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in
  /// your project dashboard.
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

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "Authorization": "Bearer \(supabaseKey)",
      "Apikey": supabaseKey,
    ].merging(options.global.headers) { _, new in new }

    auth = AuthClient(
      url: supabaseURL.appendingPathComponent("/auth/v1"),
      headers: defaultHeaders,
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

    realtime = RealtimeClient(
      supabaseURL.appendingPathComponent("/realtime/v1").absoluteString,
      headers: defaultHeaders,
      params: defaultHeaders
    )

    realtimeV2 = RealtimeClientV2(
      config: RealtimeClientV2.Configuration(
        url: supabaseURL.appendingPathComponent("/realtime/v1"),
        apiKey: supabaseKey,
        headers: defaultHeaders,
        logger: options.global.logger
      )
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
        for await (event, session) in auth.authStateChanges {
          await handleTokenChanged(event: event, session: session)
        }
      }
    )
  }

  private func handleTokenChanged(event: AuthChangeEvent, session: Session?) async {
    let supportedEvents: [AuthChangeEvent] = [.initialSession, .signedIn, .tokenRefreshed]
    guard supportedEvents.contains(event) else { return }

    realtime.setAuth(session?.accessToken)
    await realtimeV2.setAuth(session?.accessToken)
  }
}
