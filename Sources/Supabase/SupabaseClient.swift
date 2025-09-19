import Alamofire
import ConcurrencyExtras
import Foundation
import IssueReporting

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The main Supabase client that provides access to all Supabase services.
///
/// The `SupabaseClient` is the primary entry point for interacting with Supabase services
/// including Authentication, Database (PostgREST), Storage, Realtime, and Edge Functions.
/// It manages connections, authentication, and provides a unified interface to all services.
public actor SupabaseClient {
  let options: SupabaseClientOptions
  let supabaseURL: URL
  let supabaseKey: String
  let storageURL: URL
  let databaseURL: URL
  let functionsURL: URL

  private let _auth: AuthClient
  private var _database: PostgrestClient?
  private var _storage: SupabaseStorageClient?
  private var _realtime: RealtimeClient?
  private var _functions: FunctionsClient?

  /// Supabase Auth allows you to create and manage user sessions for access to data that is secured by access policies.
  ///
  /// The Auth client provides comprehensive authentication functionality including email/password,
  /// OAuth providers, multi-factor authentication, and session management.
  ///
  /// - Warning: This property is not available when the client is configured with `auth.accessToken`.
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

  /// Supabase Database provides a PostgREST client for interacting with your PostgreSQL database.
  ///
  /// The database client allows you to perform CRUD operations, execute stored procedures,
  /// and leverage PostgreSQL's advanced features through a RESTful API.
  public var database: PostgrestClient {
    if _database == nil {
      _database = PostgrestClient(
        url: databaseURL,
        schema: options.db.schema,
        headers: headers,
        logger: options.global.logger,
        session: session,
        encoder: options.db.encoder,
        decoder: options.db.decoder
      )
    }
    return _database!
  }

  /// Supabase Storage allows you to manage user-generated content, such as photos or videos.
  ///
  /// The Storage client provides functionality for uploading, downloading, and managing files
  /// in organized buckets with configurable access policies.
  public var storage: SupabaseStorageClient {
    if _storage == nil {
      _storage = SupabaseStorageClient(
        configuration: StorageClientConfiguration(
          url: storageURL,
          headers: headers,
          session: session,
          logger: options.global.logger,
          useNewHostname: options.storage.useNewHostname
        )
      )
    }
    return _storage!
  }

  /// Realtime client for Supabase that enables real-time subscriptions to database changes.
  ///
  /// The Realtime client allows you to subscribe to database changes, broadcast messages,
  /// and maintain presence information across connected clients.
  public var realtime: RealtimeClient {
    if _realtime == nil {
      _realtime = _initRealtimeClient()
    }
    return _realtime!
  }

  /// Supabase Functions allows you to deploy and invoke edge functions.
  ///
  /// The Functions client enables you to invoke serverless edge functions deployed on Supabase
  /// with support for various request types and streaming responses.
  public var functions: FunctionsClient {
    if _functions == nil {
      _functions = FunctionsClient(
        url: functionsURL,
        headers: HTTPHeaders(headers),
        region: options.functions.region.map { FunctionRegion(rawValue: $0) },
        logger: options.global.logger,
        session: session
      )
    }
    return _functions!
  }

  private let _headers: HTTPHeaders
  /// Headers provided to the inner clients on initialization.
  ///
  /// - Note: This collection is non-mutable, if you want to provide different headers, pass it in ``SupabaseClientOptions/GlobalOptions/headers``.
  public var headers: [String: String] {
    _headers.dictionary
  }

  private var listenForAuthEventsTask: Task<Void, Never>?
  private var changedAccessToken: String?

  private var session: Alamofire.Session {
    options.global.session
  }

  #if !os(Linux) && !os(Android)
    /// Create a new client.
    /// - Parameters:
    ///   - supabaseURL: The unique Supabase URL which is supplied when you create a new project in your project dashboard.
    ///   - supabaseKey: The unique Supabase Key which is supplied when you create a new project in your project dashboard.
    public init(supabaseURL: URL, supabaseKey: String) {
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

    _headers = defaultHeaders.merging(
      with: HTTPHeaders(
        [
          "Authorization": "Bearer \(supabaseKey)",
          "Apikey": supabaseKey,
        ]
      )
    )
    .merging(with: HTTPHeaders(options.global.headers))

    // TODO: Think on a different way to handle the storage key as this leads to sign outs in case of project migrations.
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
      session: options.global.session,
      autoRefreshToken: options.auth.autoRefreshToken
    )

    if options.auth.accessToken == nil {
      Task { await listenForAuthEvents() }
    }
  }

  /// Performs a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  /// - Returns: A PostgrestQueryBuilder instance.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    database.from(table)
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
    try database.rpc(fn, params: params, count: count)
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
    try database.rpc(fn, count: count)
  }

  /// Select a schema to query or perform an function (rpc) call.
  ///
  /// The schema needs to be on the list of exposed schemas inside Supabase.
  /// - Parameter schema: The schema to query.
  public func schema(_ schema: String) -> PostgrestClient {
    database.schema(schema)
  }

  /// Returns all Realtime channels.
  public var channels: [RealtimeChannel] {
    Array(realtime.channels.values)
  }

  /// Creates a Realtime channel with Broadcast, Presence, and Postgres Changes.
  /// - Parameters:
  ///   - name: The name of the Realtime channel.
  ///   - options: The options to pass to the Realtime channel.
  /// - Returns: A Realtime channel instance.
  public func channel(
    _ name: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    realtime.channel(name, options: options)
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
  ///     Task {
  ///       do {
  ///         try await supabase.handle(url)
  ///       } catch {
  ///         print("Error handling URL: \(error)")
  ///       }
  ///     }
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
  ///   Task {
  ///     do {
  ///       try await supabase.handle(url)
  ///     } catch {
  ///       print("Error handling URL: \(error)")
  ///     }
  ///   }
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
  ///   Task {
  ///     do {
  ///       try await supabase.handle(url)
  ///     } catch {
  ///       print("Error handling URL: \(error)")
  ///     }
  ///   }
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
  ///     Task {
  ///       do {
  ///         try await supabase.handle(url)
  ///       } catch {
  ///         print("Error handling URL: \(error)")
  ///       }
  ///     }
  ///   }
  /// ```
  public func handle(_ url: URL) async throws {
    try await auth.handle(url)
  }

  deinit {
    listenForAuthEventsTask?.cancel()
  }

  private func _getAccessToken() async throws -> String? {
    if let accessToken = options.auth.accessToken {
      try await accessToken()
    } else {
      try await auth.session.accessToken
    }
  }

  private func listenForAuthEvents() {
    listenForAuthEventsTask = Task {
      for await (event, session) in await auth.authStateChanges {
        await handleTokenChanged(event: event, session: session)
      }
    }
  }

  private func handleTokenChanged(event: AuthChangeEvent, session: Auth.Session?) async {
    let accessToken: String? = {
      if [.initialSession, .signedIn, .tokenRefreshed].contains(event),
        changedAccessToken != session?.accessToken
      {
        changedAccessToken = session?.accessToken
        return session?.accessToken ?? supabaseKey
      }

      if event == .signedOut {
        changedAccessToken = nil
        return supabaseKey
      }

      return nil
    }()

    await realtime.setAuth(accessToken)
  }

  private func _initRealtimeClient() -> RealtimeClient {
    var realtimeOptions = options.realtime
    realtimeOptions.headers.merge(with: _headers)

    // Use global session and logger if not specified
    if realtimeOptions.session == nil {
      realtimeOptions.session = options.global.session
    }

    if realtimeOptions.logger == nil {
      realtimeOptions.logger = options.global.logger
    }

    // Use global timeout if realtime timeout is default
    if realtimeOptions.timeoutInterval == RealtimeClientOptions.defaultTimeoutInterval {
      realtimeOptions.timeoutInterval = options.global.timeoutInterval
    }

    if realtimeOptions.accessToken == nil {
      realtimeOptions.accessToken = { [weak self] in
        try await self?._getAccessToken()
      }
    } else {
      reportIssue(
        """
        You assigned a custom `accessToken` closure to the RealtimeClient. This might not work as you expect
        as SupabaseClient uses Auth for pulling an access token to send on the realtime channels.

        Please make sure you know what you're doing.
        """
      )
    }

    return RealtimeClient(
      url: supabaseURL.appendingPathComponent("/realtime/v1"),
      options: realtimeOptions
    )
  }
}
