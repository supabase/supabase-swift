//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

public import Foundation
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

extension AuthClient {
  /// Configuration options for ``AuthClient``.
  ///
  /// ## Topics
  ///
  /// ### Networking
  /// - ``url``
  /// - ``headers``
  /// - ``flowType``
  /// - ``redirectToURL``
  /// - ``http``
  ///
  /// ### Storage
  /// - ``localStorage``
  /// - ``storageKey``
  ///
  /// ### Encoding / decoding
  /// - ``jsonEncoder``
  /// - ``jsonDecoder``
  ///
  /// ### Token refresh
  /// - ``autoRefresh``
  /// - ``observesAppLifecycle``
  /// - ``clock``
  ///
  /// ### Defaults
  /// - ``defaultFlowType``
  /// - ``defaultHeaders``
  public struct Configuration: Sendable {
    /// The URL of the Auth server.
    public let url: URL

    /// Any additional headers to send to the Auth server.
    public var headers: [String: String]

    /// The OAuth / sign-in flow type to use (``AuthFlowType/implicit`` or ``AuthFlowType/pkce``).
    public let flowType: AuthFlowType

    /// Default URL to be used for redirect on the flows that requires it.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public var storageKey: String?

    /// Provider your own local storage implementation to use instead of the default one.
    public let localStorage: any AuthLocalStorage

    /// The logger used by the Auth library. Defaults to a build-config-aware logger: visible
    /// (warning+) in debug builds, silent in release builds. Pass your own `Logging.Logger` for
    /// custom behavior — see swift-log's documentation for available `LogHandler`s.
    public let logger: Logging.Logger

    /// The JSON encoder used to serialize request bodies sent to the Auth server.
    let resolvedEncoder: JSONEncoder

    /// The JSON decoder used to deserialize responses received from the Auth server.
    let resolvedDecoder: JSONDecoder

    /// The transport and middleware chain every request goes through.
    public let http: HTTPClientConfiguration

    /// When the client refreshes the session on its own. Defaults to
    /// ``AuthClient/AutoRefreshPolicy/automatic``.
    public let autoRefresh: AutoRefreshPolicy

    /// Whether auto refresh follows the app lifecycle. Defaults to `true`.
    ///
    /// On iOS, iPadOS, tvOS, visionOS, Mac Catalyst, and watchOS, auto refresh pauses when the app
    /// enters the background, and does not start while the app launches in the background. When
    /// the app returns to the foreground, the client refreshes at once if the session is due. On
    /// macOS it checks each time the app becomes active, and it does not pause. Other platforms have no
    /// app lifecycle, so this has no effect there. Set it to `false` to drive auto refresh with
    /// ``AuthClient/startAutoRefresh()`` and ``AuthClient/stopAutoRefresh()`` yourself, for
    /// example from a SwiftUI `scenePhase` change.
    ///
    /// Whatever its value, on iOS, iPadOS, tvOS, visionOS, and Mac Catalyst the client reads
    /// storage again when protected data becomes available, so a session that a locked Keychain
    /// hid at launch loads once the device unlocks. watchOS, macOS, and other platforms post no
    /// such notification. There, the client reads storage again only when a call needs the
    /// session: ``AuthClient/session``, ``AuthClient/refreshSessionIfNeeded()``, a request that
    /// sends the session's access token, a new ``AuthClient/events()`` stream, or
    /// ``AuthClient/initialization()``.
    public let observesAppLifecycle: Bool

    /// The clock auto refresh sleeps on until the refresh is due, and between retries.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive token refresh
    /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
    /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
    /// yourself, as this package does not export it.
    public let clock: any Clock<Duration>

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
    ///   - storageKey: Optional key name used for storing tokens in local storage.
    ///   - localStorage: The storage mechanism for local data.
    ///   - logger: The logger to use. Defaults to a build-config-aware logger — see `Configuration.logger`.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - autoRefresh: When the client refreshes the session on its own.
    ///   - observesAppLifecycle: Whether auto refresh pauses in the background and resumes in the
    ///     foreground.
    ///   - clock: The clock auto refresh sleeps on. Defaults to `ContinuousClock()`.
    public init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      http: HTTPClientConfiguration = .init(),
      autoRefresh: AutoRefreshPolicy = .automatic,
      observesAppLifecycle: Bool = true,
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self.init(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        resolvedEncoder: AuthClient.Configuration.jsonEncoder,
        resolvedDecoder: AuthClient.Configuration.jsonDecoder,
        http: http,
        autoRefresh: autoRefresh,
        observesAppLifecycle: observesAppLifecycle,
        clock: clock
      )
    }

    /// Designated initializer that stores the resolved JSON encoder/decoder.
    ///
    /// Kept internal since customizing Auth's JSON encoding/decoding is not a
    /// publicly supported customization point.
    init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      resolvedEncoder: JSONEncoder,
      resolvedDecoder: JSONDecoder,
      http: HTTPClientConfiguration = .init(),
      autoRefresh: AutoRefreshPolicy = .automatic,
      observesAppLifecycle: Bool = true,
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url ?? defaultAuthURL
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      var logger = logger
      logger[metadataKey: "system"] = "auth"
      self.logger = logger
      self.resolvedEncoder = resolvedEncoder
      self.resolvedDecoder = resolvedDecoder
      self.http = http
      self.autoRefresh = autoRefresh
      self.observesAppLifecycle = observesAppLifecycle
      self.clock = clock
    }
  }

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type..
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data..
  ///   - logger: The logger to use. Defaults to a build-config-aware logger — see `Configuration.logger`.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - autoRefresh: When the client refreshes the session on its own.
  ///   - observesAppLifecycle: Whether auto refresh pauses in the background and resumes in the
  ///     foreground.
  ///   - clock: The clock auto refresh sleeps on. Defaults to `ContinuousClock()`.
  public convenience init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
    http: HTTPClientConfiguration = .init(),
    autoRefresh: AutoRefreshPolicy = .automatic,
    observesAppLifecycle: Bool = true,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        http: http,
        autoRefresh: autoRefresh,
        observesAppLifecycle: observesAppLifecycle,
        clock: clock
      )
    )
  }
}
