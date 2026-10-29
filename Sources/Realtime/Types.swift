//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

public import Foundation
package import HTTPTypes
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// Options for initializing ``RealtimeClient``.
///
/// Use this struct to customize the behavior of the Realtime client, including connection
/// timing, authentication, and app lifecycle handling.
///
/// ```swift
/// let options = RealtimeClientOptions(
///   heartbeatInterval: .seconds(30),
///   handleAppLifecycle: true
/// )
/// let client = RealtimeClient(url: realtimeURL, options: options)
/// ```
///
/// ## Topics
/// ### Lifecycle
/// - ``handleAppLifecycle``
/// ### Default Values
/// - ``defaultHeartbeatInterval``
/// - ``defaultReconnectBackoff``
/// - ``defaultRequestTimeout``
/// - ``defaultConnectOnSubscribe``
/// - ``defaultDisconnectOnEmptyChannelsAfter``
/// - ``defaultHandleAppLifecycle``
/// ### Initialization
/// - ``init(headers:heartbeatInterval:reconnectBackoff:requestTimeout:connectOnSubscribe:disconnectOnEmptyChannelsAfter:serverLogLevel:http:accessToken:logger:session:handleAppLifecycle:clock:)``
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPFields

  /// How often the client sends a heartbeat to keep the connection alive.
  ///
  /// When a heartbeat has no reply by the next one, the client treats the socket as dead,
  /// closes it, and reconnects. So a dead socket is found within two intervals. Lower this
  /// value to find one sooner, at the cost of more traffic.
  public var heartbeatInterval: Duration

  /// How long the client waits before each reconnect attempt after the connection drops.
  ///
  /// Attempts never stop while the client wants a connection. The attempt count starts again
  /// after a successful connect.
  public var reconnectBackoff: BackoffPolicy

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
  /// When enabled, the client observes platform lifecycle notifications and — on
  /// foregrounding — reconnects and re-joins any existing channels if the WebSocket
  /// was closed while the app was backgrounded. The client does not proactively
  /// disconnect on backgrounding; short background/foreground cycles keep the
  /// connection alive without churn.
  ///
  /// Disable this to manage the connection yourself with ``RealtimeClient/connect()`` and
  /// ``RealtimeClient/disconnect(code:reason:)``.
  ///
  /// Default: `true` on iOS, macOS, tvOS, and visionOS. `false` on other platforms
  /// (including watchOS and Linux), where lifecycle observation is not supported.
  public var handleAppLifecycle: Bool

  /// How much the Realtime server logs for this connection. `nil`, the default, keeps the
  /// server's own level.
  public var serverLogLevel: RealtimeServerLogLevel?
  package var http: HTTPClientConfiguration
  package var accessToken: (@Sendable () async throws -> String?)?
  package var logger: Logging.Logger

  /// The clock the heartbeat timer and reconnect backoff sleep on.
  ///
  /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive those behaviors
  /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
  /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
  /// yourself, as this package does not export it.
  public var clock: any Clock<Duration>

  /// A template `URLSession` used to configure the Realtime WebSocket connection.
  ///
  /// Realtime never uses this session object directly — it always creates its own dedicated
  /// internal session, copying this session's `configuration` and forwarding its `delegate`'s
  /// auth-challenge callback (if any). Pass the same preconfigured `URLSession` used
  /// elsewhere in your app (e.g. one with a `URLSessionDelegate` implementing certificate
  /// pinning) to apply the same trust evaluation to Realtime's WebSocket connection.
  /// Defaults to `nil` (equivalent to `.default` configuration with no delegate to forward).
  package var session: URLSession?

  /// Default interval between heartbeat messages sent to keep the connection alive.
  public static let defaultHeartbeatInterval: Duration = .seconds(25)

  /// Default for ``reconnectBackoff``: a full-jitter wait with a 1 s base and a 30 s cap.
  public static let defaultReconnectBackoff: BackoffPolicy = .fullJitter(
    base: .seconds(1), cap: .seconds(30))

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

  /// Default value for ``handleAppLifecycle``.
  ///
  /// Returns `true` on iOS, macOS, tvOS, and visionOS; `false` on all other platforms.
  public static let defaultHandleAppLifecycle: Bool = {
    #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
      return true
    #else
      return false
    #endif
  }()

  /// Creates a new ``RealtimeClientOptions`` with the specified configuration.
  ///
  /// - Parameters:
  ///   - headers: Additional HTTP headers sent with each WebSocket upgrade request.
  ///   - heartbeatInterval: Interval between heartbeat messages. Defaults to ``defaultHeartbeatInterval``.
  ///   - reconnectBackoff: The wait before each reconnect attempt. Defaults to ``defaultReconnectBackoff``.
  ///   - requestTimeout: How long to wait for the server to answer a request. Defaults to ``defaultRequestTimeout``.
  ///   - connectOnSubscribe: Whether to automatically call ``RealtimeClient/connect()`` when subscribing to a channel. Defaults to ``defaultConnectOnSubscribe``.
  ///   - disconnectOnEmptyChannelsAfter: How long to wait before disconnecting when all channels are removed. Defaults to ``defaultDisconnectOnEmptyChannelsAfter``.
  ///   - serverLogLevel: How much the Realtime server logs for this connection. Defaults to `nil`.
  ///   - http: The transport and middleware chain REST broadcast calls go through.
  ///   - accessToken: Optional async closure that returns the current access token.
  ///   - logger: The logger used for Realtime client diagnostics. Defaults to a logger labeled `"io.supabase.realtime"`.
  ///   - session: A template `URLSession` to configure the WebSocket connection from. Defaults to `nil`.
  ///   - handleAppLifecycle: Whether to automatically reconnect on app foreground. Defaults to ``defaultHandleAppLifecycle``.
  ///   - clock: The clock the heartbeat timer and reconnect backoff sleep on. Defaults to
  ///     `ContinuousClock()`; pass a `TestClock` from swift-clocks (add it to your
  ///     test target yourself) to drive them deterministically in tests.
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: Duration = Self.defaultHeartbeatInterval,
    reconnectBackoff: BackoffPolicy = Self.defaultReconnectBackoff,
    requestTimeout: Duration = Self.defaultRequestTimeout,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    disconnectOnEmptyChannelsAfter: Duration = Self.defaultDisconnectOnEmptyChannelsAfter,
    serverLogLevel: RealtimeServerLogLevel? = nil,
    http: HTTPClientConfiguration = .init(),
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.realtime"),
    session: URLSession? = nil,
    handleAppLifecycle: Bool = Self.defaultHandleAppLifecycle,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectBackoff = reconnectBackoff
    self.requestTimeout = requestTimeout
    self.connectOnSubscribe = connectOnSubscribe
    self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
    self.handleAppLifecycle = handleAppLifecycle
    self.serverLogLevel = serverLogLevel
    self.http = http
    self.accessToken = accessToken
    var logger = logger
    logger[metadataKey: "system"] = "realtime"
    self.logger = logger
    self.session = session
    self.clock = clock
  }

  var apikey: String? {
    headers[.apiKey]
  }
}

/// The subscription state of a ``RealtimeChannel``, with the reason when there is one.
///
/// The set of cases is fixed until the next major version, so a `switch` needs no `default`.
/// The type is not `Equatable`: use ``isSubscribed`` and ``error``, or match a case.
///
/// ```swift
/// for await status in await channel.statusChanges() {
///   switch status {
///   case .resubscribing(_, let retryIn, let lastError):
///     print("Joining again in \(retryIn) after: \(lastError.message)")
///   case .failed(let error):
///     print("Gave up: \(error.message)")
///   default:
///     break
///   }
/// }
/// ```
///
/// ## Topics
/// ### States
/// - ``unsubscribed``
/// - ``subscribing(attempt:)``
/// - ``subscribed``
/// - ``resubscribing(attempt:retryIn:lastError:)``
/// - ``unsubscribing``
/// - ``failed(_:)``
/// ### Predicates
/// - ``isSubscribed``
/// - ``error``
public enum RealtimeChannelStatus: Sendable {
  /// The channel has not joined the topic, or has left it.
  case unsubscribed

  /// The channel sent `phx_join` and waits for the server to confirm it. Attempt 1 is the
  /// first join of a ``RealtimeChannel/subscribe()`` call; later attempts are rejoins.
  case subscribing(attempt: Int)

  /// The server confirmed the join. The channel receives events.
  case subscribed

  /// Join attempt `attempt` failed with `lastError`. The channel joins again after `retryIn`.
  case resubscribing(attempt: Int, retryIn: Duration, lastError: RealtimeError)

  /// The channel sent `phx_leave` and waits for the server to close it.
  case unsubscribing

  /// ``RealtimeChannel/subscribe()`` stopped because a retry cannot help. Call it again to
  /// start over.
  case failed(RealtimeError)

  /// Whether the channel is ``subscribed``.
  public var isSubscribed: Bool {
    if case .subscribed = self { true } else { false }
  }

  /// The error behind ``resubscribing(attempt:retryIn:lastError:)`` or ``failed(_:)``, or `nil`.
  public var error: RealtimeError? {
    switch self {
    case .resubscribing(_, _, let error), .failed(let error): error
    case .unsubscribed, .subscribing, .subscribed, .unsubscribing: nil
    }
  }
}

extension RealtimeChannelStatus {
  /// Whether `other` is the same case with the same values, so a repeat is not emitted.
  func isSame(as other: RealtimeChannelStatus) -> Bool {
    switch (self, other) {
    case (.unsubscribed, .unsubscribed), (.subscribed, .subscribed),
      (.unsubscribing, .unsubscribing):
      true
    case (.subscribing(let a), .subscribing(let b)):
      a == b
    case (.resubscribing(let a, let da, let ea), .resubscribing(let b, let db, let eb)):
      a == b && da == db && ea.isSameFailure(as: eb)
    case (.failed(let a), .failed(let b)):
      a.isSameFailure(as: b)
    default:
      false
    }
  }
}

/// The connection state of a ``RealtimeClient``, with the reason when there is one.
///
/// The set of cases is fixed until the next major version, so a `switch` needs no `default`.
/// The type is not `Equatable`: use ``isConnected`` and ``error``, or match a case.
///
/// ```swift
/// for await status in await client.statusChanges() {
///   if case .reconnecting(let attempt, let retryIn, _) = status {
///     print("Attempt \(attempt + 1) in \(retryIn)")
///   }
/// }
/// ```
///
/// ## Topics
/// ### States
/// - ``disconnected(_:)``
/// - ``connecting(attempt:)``
/// - ``connected``
/// - ``reconnecting(attempt:retryIn:lastError:)``
/// ### Predicates
/// - ``isConnected``
/// - ``error``
public enum RealtimeClientStatus: Sendable {
  /// The WebSocket is closed. The error is set when a failure, not the caller, closed it.
  case disconnected(RealtimeError?)

  /// The client is opening the WebSocket. Attempt 1 is the caller's
  /// ``RealtimeClient/connect()``; later attempts reconnect after a drop.
  case connecting(attempt: Int)

  /// The WebSocket is open.
  case connected

  /// Connection attempt `attempt` failed or the socket dropped with `lastError`. The client
  /// opens the WebSocket again after `retryIn`.
  case reconnecting(attempt: Int, retryIn: Duration, lastError: RealtimeError)

  /// Whether the client is ``connected``.
  public var isConnected: Bool {
    if case .connected = self { true } else { false }
  }

  /// The error behind ``disconnected(_:)`` or ``reconnecting(attempt:retryIn:lastError:)``,
  /// or `nil`.
  public var error: RealtimeError? {
    switch self {
    case .disconnected(let error): error
    case .reconnecting(_, _, let error): error
    case .connecting, .connected: nil
    }
  }
}

/// A server event about a ``RealtimeChannel``, emitted by ``RealtimeChannel/events()``.
///
/// ## Topics
/// ### Events
/// - ``resubscribed``
/// - ``postgresChangesReady``
/// - ``postgresChangesFailed(_:)``
/// - ``replicationReady``
/// - ``replicationFailed(_:)``
public enum RealtimeChannelEvent: Sendable, Equatable {
  /// The channel joined again after it was subscribed, for example after a reconnect. Events
  /// sent while it was away were missed; reload any state built from them.
  case resubscribed

  /// The server set up the channel's Postgres changes subscriptions ("Subscribed to
  /// PostgreSQL"). Changes from now on are delivered.
  case postgresChangesReady

  /// The server could not set up the channel's Postgres changes subscriptions. The channel
  /// stays subscribed, so broadcast and presence keep working. The value is the server's
  /// message.
  case postgresChangesFailed(String)

  /// The Postgres replication connection behind the channel is ready ("Replication connection
  /// established"). The server sends it only when you opt in with
  /// ``BroadcastJoinConfig/replicationReady``.
  case replicationReady

  /// The Postgres replication connection did not become ready in time. The server sends it only
  /// when you opt in with ``BroadcastJoinConfig/replicationReady``. The value is the server's
  /// message.
  case replicationFailed(String)
}

/// One step of the heartbeat cycle, emitted by ``RealtimeClient/heartbeats()``.
///
/// The client sends a heartbeat every ``RealtimeClientOptions/defaultHeartbeatInterval``. When
/// the next one is due and the server has not acknowledged the previous one, the client
/// reports ``timedOut`` and reconnects.
///
/// ## Topics
/// ### Events
/// - ``sent``
/// - ``acknowledged(latency:)``
/// - ``timedOut``
public enum HeartbeatEvent: Sendable, Equatable {
  /// The client sent a heartbeat.
  case sent

  /// The server acknowledged the heartbeat `latency` after it was sent.
  case acknowledged(latency: Duration)

  /// The server did not acknowledge the previous heartbeat in time. The client drops the
  /// socket and reconnects.
  case timedOut
}

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// How much the Realtime server logs for one connection.
///
/// Set it on ``RealtimeClientOptions/serverLogLevel``. The client sends it as the `log_level`
/// query item of the WebSocket URL. It does not change what the client's own `logger` prints.
///
/// The type is open: a level this SDK has no member for still works.
///
/// ```swift
/// var options = RealtimeClientOptions()
/// options.serverLogLevel = .warning
/// ```
///
/// ## Topics
/// ### Levels
/// - ``info``
/// - ``warning``
/// - ``error``
public struct RealtimeServerLogLevel: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value sent as the `log_level` query item.
  public let rawValue: String

  /// Creates a level from its raw value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a level from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Informational messages and above.
  public static let info: RealtimeServerLogLevel = "info"

  /// Warnings and errors. Sent as `warn`.
  public static let warning: RealtimeServerLogLevel = "warn"

  /// Errors only.
  public static let error: RealtimeServerLogLevel = "error"
}
