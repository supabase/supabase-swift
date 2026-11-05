//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

public import Foundation
public import HTTPTypes
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
  /// - ``redirectTo``
  /// - ``http``
  ///
  /// ### Storage
  /// - ``storage``
  /// - ``storageKey``
  ///
  /// ### Token refresh
  /// - ``autoRefresh``
  /// - ``observesAppLifecycle``
  /// - ``initialRefreshTimeout``
  ///
  /// ### Testing
  /// - ``clock``
  /// - ``now``
  public struct Configuration: Sendable {
    /// The URL of the Auth server, such as `https://<project>.supabase.co/auth/v1`.
    public var url: URL

    /// Headers to send with every request, such as the `apikey` header. The client adds
    /// `X-Client-Info` unless this sets it.
    public var headers: HTTPFields

    /// Where the client persists the session and its pending flows. Defaults to
    /// ``KeychainStorage`` on Apple platforms and ``InMemoryAuthStorage`` elsewhere.
    public var storage: any AuthStorage

    /// The key the client stores the session under. Clients that share a ``storage`` need
    /// different keys. `SupabaseClient` derives `sb-<project-ref>-auth-token` from its URL.
    public var storageKey: String

    /// Default URL to be used for redirect on the flows that requires it.
    public var redirectTo: URL?

    /// The logger used by the Auth library. Defaults to a build-config-aware logger: visible
    /// (warning+) in debug builds, silent in release builds. Pass your own `Logging.Logger` for
    /// custom behavior — see swift-log's documentation for available `LogHandler`s.
    public var logger: Logging.Logger

    /// The transport and middleware chain every request goes through.
    public var http: HTTPClientConfiguration

    /// When the client refreshes the session on its own. Defaults to
    /// ``AuthClient/AutoRefreshPolicy/automatic``.
    public var autoRefresh: AutoRefreshPolicy

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
    /// Auto refresh follows the app lifecycle only when ``autoRefresh`` is
    /// ``AuthClient/AutoRefreshPolicy/automatic``. Under another policy the client does not
    /// refresh on its own, so the lifecycle has nothing to pause or resume.
    ///
    /// Whether this is `true` or `false`, and under every ``autoRefresh`` policy, on iOS, iPadOS,
    /// tvOS, visionOS, and Mac Catalyst the client reads storage again when protected data becomes
    /// available, so a session that a locked Keychain hid at launch loads once the device unlocks.
    /// watchOS, macOS, and other platforms post no such notification. There, the client reads
    /// storage again only when a call needs the session: ``AuthClient/session()``,
    /// ``AuthClient/refreshSessionIfNeeded()``, a request that sends the session's access token, a
    /// new ``AuthClient/events()`` stream, or ``AuthClient/initialization()``.
    public var observesAppLifecycle: Bool

    /// The clock auto refresh sleeps on until the refresh is due, and between retries.
    ///
    /// Keep it in step with ``now``: the refresh deadline sleeps on this clock, and expiry checks
    /// read ``now``.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive token refresh
    /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
    /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
    /// yourself, as this package does not export it.
    public var clock: any Clock<Duration>

    /// The time source for every expiry check and every receipt time the client records.
    ///
    /// Defaults to the system clock. Pass a fixed or stepped time in tests, together with a
    /// ``clock`` you control.
    public var now: @Sendable () -> Date

    /// How long the client waits, when it is created with an expired stored session, for one
    /// refresh of that session before it delivers ``AuthEvent/initialSession``.
    ///
    /// Defaults to 5 seconds. A refresh that finishes in time makes the initial session the
    /// refreshed one. A refresh that fails, or does not finish in time, makes it the expired
    /// session. A refresh that is still running then commits as ``AuthEvent/tokenRefreshed``. The
    /// wait uses ``clock``.
    ///
    /// The client refreshes at start-up only under ``AuthClient/AutoRefreshPolicy/automatic``. A
    /// value of zero or less turns it off.
    public var initialRefreshTimeout: Duration

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - url: The URL of the Auth server.
    ///   - storageKey: The key the session is stored under.
    ///   - headers: Headers to send with every request.
    ///   - storage: Where the client persists the session. `nil` uses the platform's default.
    ///   - redirectTo: Default URL to be used for redirect on the flows that requires it.
    ///   - logger: The logger to use. Defaults to a build-config-aware logger — see ``logger``.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - autoRefresh: When the client refreshes the session on its own.
    ///   - observesAppLifecycle: Whether auto refresh pauses in the background and resumes in the
    ///     foreground.
    ///   - clock: The clock auto refresh sleeps on. Defaults to `ContinuousClock()`.
    ///   - now: The time source for expiry checks. Defaults to the system clock.
    ///   - initialRefreshTimeout: How long to wait for the refresh of an expired stored session
    ///     before ``AuthEvent/initialSession``. Defaults to 5 seconds.
    public init(
      url: URL,
      storageKey: String,
      headers: HTTPFields = [:],
      storage: (any AuthStorage)? = nil,
      redirectTo: URL? = nil,
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      http: HTTPClientConfiguration = .init(),
      autoRefresh: AutoRefreshPolicy = .automatic,
      observesAppLifecycle: Bool = true,
      clock: any Clock<Duration> = ContinuousClock(),
      now: @escaping @Sendable () -> Date = { Date() },
      initialRefreshTimeout: Duration = .seconds(5)
    ) {
      self.url = url
      self.storageKey = storageKey
      self.headers = headers
      self.storage = storage ?? AuthPlatform.defaultStorage
      self.redirectTo = redirectTo
      var logger = logger.redactingSecrets()
      logger[metadataKey: "system"] = "auth"
      self.logger = logger
      self.http = http
      self.autoRefresh = autoRefresh
      self.observesAppLifecycle = observesAppLifecycle
      self.clock = clock
      self.now = now
      self.initialRefreshTimeout = initialRefreshTimeout
    }
  }
}
