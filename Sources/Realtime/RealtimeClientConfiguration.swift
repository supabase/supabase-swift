public import Foundation
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

extension RealtimeClient {
  /// The settings a ``RealtimeClient`` is created with.
  ///
  /// Every setting but ``url`` has a default, and each can be read and changed after creation.
  ///
  /// ```swift
  /// var configuration = RealtimeClient.Configuration(
  ///   url: realtimeURL,
  ///   accessToken: { try await currentToken() }
  /// )
  /// configuration.heartbeatInterval = .seconds(15)
  /// configuration.serverLogLevel = .warning
  /// let client = try RealtimeClient(configuration: configuration)
  /// ```
  ///
  /// ## Topics
  /// ### Connection
  /// - ``url``
  /// - ``headers``
  /// - ``accessToken``
  /// - ``webSocketTransport``
  /// - ``http``
  /// ### Timing
  /// - ``heartbeatInterval``
  /// - ``requestTimeout``
  /// - ``disconnectOnEmptyChannelsAfter``
  /// ### Behavior
  /// - ``connectOnSubscribe``
  /// - ``observesAppLifecycle``
  /// - ``monitorsNetworkPath``
  /// ### Logging
  /// - ``logger``
  /// - ``serverLogLevel``
  /// ### Testing
  /// - ``clock``
  /// ### Default Values
  /// - ``defaultHeartbeatInterval``
  /// - ``defaultRequestTimeout``
  /// - ``defaultConnectOnSubscribe``
  /// - ``defaultDisconnectOnEmptyChannelsAfter``
  /// - ``defaultObservesAppLifecycle``
  /// - ``defaultMonitorsNetworkPath``
  /// ### Initialization
  /// - ``init(url:headers:heartbeatInterval:requestTimeout:connectOnSubscribe:disconnectOnEmptyChannelsAfter:observesAppLifecycle:monitorsNetworkPath:serverLogLevel:accessToken:webSocketTransport:http:logger:clock:)``
  public struct Configuration: Sendable {
    /// The Realtime server URL, such as `https://<project>.supabase.co/realtime/v1`.
    public var url: URL

    /// Headers sent with the WebSocket upgrade request and with every `RealtimeChannel.httpSend`
    /// request.
    ///
    /// Header names compare without regard to case. `SupabaseClient` passes its own headers, such
    /// as `apikey`, merged under `SupabaseClient.Configuration.Realtime.headers`. The client
    /// adds an `X-Client-Info` header unless you set that header yourself.
    public var headers: HTTPFields

    /// How often the client sends a heartbeat to keep the connection alive.
    ///
    /// When a heartbeat has no reply by the next one, the client treats the socket as dead,
    /// closes it, and reconnects. So a dead socket is found within two intervals. Lower this
    /// value to find one sooner, at the cost of more traffic.
    public var heartbeatInterval: Duration

    /// How long the client waits for the server to answer a request.
    ///
    /// This bounds:
    /// - each attempt to join a channel; a timed-out join is retried,
    /// - a push that expects a reply, such as a broadcast with acknowledgement, `track` or
    ///   `untrack`,
    /// - the leave in ``RealtimeChannel/unsubscribe()``,
    /// - a `RealtimeChannel.httpSend` call without its own `timeout`,
    /// - each call to the ``accessToken`` callback.
    public var requestTimeout: Duration

    /// Whether ``RealtimeChannel/subscribe()`` calls ``RealtimeClient/connect()`` when the client
    /// is not connected.
    public var connectOnSubscribe: Bool

    /// How long the client keeps the socket open after the last channel is removed.
    ///
    /// A channel created within this time reuses the socket and cancels the disconnect. `.zero`
    /// disconnects at once.
    public var disconnectOnEmptyChannelsAfter: Duration

    /// Whether to automatically handle app lifecycle changes (background/foreground).
    ///
    /// When enabled, the client observes platform lifecycle notifications. When the app returns to
    /// the foreground, it checks that a connected socket still answers: it sends a heartbeat at
    /// once and, if the server does not reply within 5 seconds, closes the socket and reconnects
    /// without waiting out a backoff. It also reconnects and re-joins any existing channels if the
    /// WebSocket was closed while the app was backgrounded. The client does not proactively
    /// disconnect on backgrounding; short background/foreground cycles keep the connection alive
    /// without churn.
    ///
    /// On macOS the foreground signal is the machine waking from sleep, because a Mac app that
    /// loses focus keeps its connection.
    ///
    /// Disable this to manage the connection yourself with ``RealtimeClient/connect()`` and
    /// ``RealtimeClient/disconnect(code:reason:)``.
    ///
    /// Default: `true` on iOS, macOS, tvOS, and visionOS. `false` on watchOS, where you can turn it
    /// on, and on Linux and Android, where it does nothing.
    public var observesAppLifecycle: Bool

    /// Whether to watch the network path and reconnect as soon as the network is back.
    ///
    /// When enabled, a report that the network path is satisfied cuts the wait before the next
    /// reconnect attempt short, but never to less than 2 seconds after the last attempt started, so
    /// a path that flaps cannot start an attempt per report. The hint only shortens a wait: the
    /// client never refuses to connect because the monitor reports no path, and it ignores the
    /// hint while it is connected, connecting, or disconnected.
    ///
    /// Default: `true` on iOS, macOS, tvOS, and visionOS. `false` on other platforms. watchOS
    /// keeps reporting an unsatisfied path to ordinary apps, so the hint may never fire there.
    /// Linux has no path monitor, so the option has no effect there.
    public var monitorsNetworkPath: Bool

    /// How much the Realtime server logs for this connection. `nil`, the default, keeps the
    /// server's own level.
    public var serverLogLevel: RealtimeServerLogLevel?

    /// The transport and middleware chain that `RealtimeChannel.httpSend` calls go through.
    ///
    /// An `httpSend` request has two timeouts:
    /// - Its own `timeout`, or ``requestTimeout``, bounds the request. When it runs out, the call
    ///   throws ``RealtimeError`` with kind `.timeout`.
    /// - The ``HTTPClientConfiguration/timeout`` set here is the idle timeout. When no data moves
    ///   for that long, the call throws ``RealtimeError`` with kind `.transport` and
    ///   `URLError(.timedOut)` in `underlyingError`.
    ///
    /// The WebSocket does not use it; see ``webSocketTransport``.
    public var http: HTTPClientConfiguration

    /// Returns the access token channels join with and `httpSend` sends.
    ///
    /// The client calls it before a join, when a heartbeat goes out, and one minute before the
    /// token's `exp`, at most once every 10 seconds. A call that throws, returns `nil`, or does not
    /// return within ``requestTimeout`` keeps the current token. `SupabaseClient` sets it to the
    /// signed-in user's token.
    ///
    /// `httpSend` calls it for every request. If it throws, `httpSend` throws ``RealtimeError``
    /// with kind ``RealtimeError/Kind-swift.struct/accessToken``.
    ///
    /// This is Realtime's only token source. Do not add an `AccessTokenMiddleware` to ``http``.
    public var accessToken: (@Sendable () async throws -> String?)?

    /// The logger for the client's own diagnostics.
    ///
    /// Defaults to a build-config-aware logger labeled `"io.supabase.realtime"`. `SupabaseClient`
    /// passes the facade Realtime logger, or its global logger when that is `nil`. The client tags the logger it uses with the `system`
    /// metadata key set to `realtime`. The client removes tokens, secrets, and URL query strings
    /// from each line before your handler sees it.
    public var logger: Logging.Logger

    /// The WebSocket stack the client connects with.
    ///
    /// `nil`, the default, uses ``URLSessionWebSocketTransport``. Set a configured
    /// `URLSessionWebSocketTransport` to pin certificates, or your own ``WebSocketTransport``
    /// to use another stack. A custom transport must follow the error contract that
    /// ``WebSocketTransport`` describes.
    public var webSocketTransport: (any WebSocketTransport)?

    /// The clock the heartbeat timer and reconnect backoff sleep on.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive those behaviors
    /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
    /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
    /// yourself, as this package does not export it.
    public var clock: any Clock<Duration>

    /// Default interval between heartbeat messages sent to keep the connection alive.
    public static let defaultHeartbeatInterval: Duration = .seconds(25)

    /// Default for ``requestTimeout``: 10 seconds.
    public static let defaultRequestTimeout: Duration = .seconds(10)

    /// Default for whether to automatically connect the socket when subscribing to a channel.
    public static let defaultConnectOnSubscribe: Bool = true

    /// Defers the WebSocket disconnect after the last channel is removed, giving a window to reuse
    /// the existing connection when switching channels without a reconnect penalty. Defaults to
    /// `2 × defaultHeartbeatInterval`. Set to `.zero` for immediate disconnect. If a new channel is
    /// created before the timer fires, the pending disconnect is cancelled.
    public static let defaultDisconnectOnEmptyChannelsAfter: Duration =
      defaultHeartbeatInterval * 2

    /// Default value for ``observesAppLifecycle``.
    ///
    /// Returns `true` on iOS, macOS, tvOS, and visionOS; `false` on all other platforms.
    public static let defaultObservesAppLifecycle: Bool = {
      #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
        return true
      #else
        return false
      #endif
    }()

    /// Default value for ``monitorsNetworkPath``.
    ///
    /// Returns `true` on iOS, macOS, tvOS, and visionOS; `false` on all other platforms.
    public static let defaultMonitorsNetworkPath: Bool = {
      #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
        return true
      #else
        return false
      #endif
    }()

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - url: The Realtime server URL, such as `https://<project>.supabase.co/realtime/v1`.
    ///   - headers: Additional HTTP headers sent with each WebSocket upgrade request.
    ///   - heartbeatInterval: Interval between heartbeat messages. Defaults to ``defaultHeartbeatInterval``.
    ///   - requestTimeout: How long to wait for the server to answer a request. Defaults to ``defaultRequestTimeout``.
    ///   - connectOnSubscribe: Whether to automatically call ``RealtimeClient/connect()`` when subscribing to a channel. Defaults to ``defaultConnectOnSubscribe``.
    ///   - disconnectOnEmptyChannelsAfter: How long to wait before disconnecting when all channels are removed. Defaults to ``defaultDisconnectOnEmptyChannelsAfter``.
    ///   - observesAppLifecycle: Whether to automatically reconnect on app foreground. Defaults to ``defaultObservesAppLifecycle``.
    ///   - monitorsNetworkPath: Whether to reconnect as soon as the network path is satisfied again. Defaults to ``defaultMonitorsNetworkPath``.
    ///   - serverLogLevel: How much the Realtime server logs for this connection. Defaults to `nil`.
    ///   - accessToken: Optional async closure that returns the current access token.
    ///   - webSocketTransport: The WebSocket stack to connect with. Defaults to `nil`, which uses ``URLSessionWebSocketTransport``.
    ///   - http: The transport and middleware chain REST broadcast calls go through.
    ///   - logger: The logger used for Realtime client diagnostics. Defaults to a logger labeled `"io.supabase.realtime"`.
    ///   - clock: The clock the heartbeat timer and reconnect backoff sleep on. Defaults to
    ///     `ContinuousClock()`; pass a `TestClock` from swift-clocks (add it to your
    ///     test target yourself) to drive them deterministically in tests.
    public init(
      url: URL,
      headers: HTTPFields = [:],
      heartbeatInterval: Duration = Self.defaultHeartbeatInterval,
      requestTimeout: Duration = Self.defaultRequestTimeout,
      connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
      disconnectOnEmptyChannelsAfter: Duration = Self.defaultDisconnectOnEmptyChannelsAfter,
      observesAppLifecycle: Bool = Self.defaultObservesAppLifecycle,
      monitorsNetworkPath: Bool = Self.defaultMonitorsNetworkPath,
      serverLogLevel: RealtimeServerLogLevel? = nil,
      accessToken: (@Sendable () async throws -> String?)? = nil,
      webSocketTransport: (any WebSocketTransport)? = nil,
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.realtime"),
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self.url = url
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.requestTimeout = requestTimeout
      self.connectOnSubscribe = connectOnSubscribe
      self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
      self.observesAppLifecycle = observesAppLifecycle
      self.monitorsNetworkPath = monitorsNetworkPath
      self.serverLogLevel = serverLogLevel
      self.accessToken = accessToken
      self.webSocketTransport = webSocketTransport
      self.http = http
      self.logger = logger
      self.clock = clock
    }
  }
}
