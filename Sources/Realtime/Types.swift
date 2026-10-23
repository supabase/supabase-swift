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
/// - ``defaultReconnectDelay``
/// - ``defaultTimeout``
/// - ``defaultConnectOnSubscribe``
/// - ``defaultMaxRetryAttempts``
/// - ``defaultDisconnectOnEmptyChannelsAfter``
/// - ``defaultHandleAppLifecycle``
/// ### Initialization
/// - ``init(headers:heartbeatInterval:reconnectDelay:timeout:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:logLevel:http:accessToken:logger:session:handleAppLifecycle:clock:)``
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPFields
  var heartbeatInterval: Duration
  var reconnectDelay: Duration
  var timeout: Duration
  var connectOnSubscribe: Bool
  var maxRetryAttempts: Int
  var disconnectOnEmptyChannelsAfter: Duration

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

  /// Sets the log level for Realtime
  var logLevel: LogLevel?
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

  /// Default base delay for reconnecting after a connection drop. The first
  /// attempt waits a random duration between half of this and this; later attempts double the
  /// range (capped at 30s) until the connection is reestablished.
  public static let defaultReconnectDelay: Duration = .seconds(7)

  /// Default maximum time to wait for a server reply before treating a request as timed out.
  ///
  /// Also the shortest wait for a join reply, whatever `timeout` the options hold.
  public static let defaultTimeout: Duration = .seconds(10)

  /// Default for whether to automatically connect the socket when subscribing to a channel.
  public static let defaultConnectOnSubscribe: Bool = true

  /// Default maximum number of subscribe retry attempts before giving up.
  public static let defaultMaxRetryAttempts: Int = 5

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
  ///   - reconnectDelay: Base delay for reconnecting after a disconnection. The first attempt waits a random duration between half of this and this; later attempts double the range (capped at 30s). The client stops after `maxRetryAttempts` failures in a row, on HTTP 401, 403, or 404, and on a close code of 4000 or above. Defaults to ``defaultReconnectDelay``.
  ///   - timeout: Maximum time to wait for a server reply. A join waits at least
  ///     ``defaultTimeout``, because the server can hold its answer to a rejected join for a few
  ///     seconds. Defaults to ``defaultTimeout``.
  ///   - connectOnSubscribe: Whether to automatically call ``RealtimeClient/connect()`` when subscribing to a channel. Defaults to ``defaultConnectOnSubscribe``.
  ///   - maxRetryAttempts: Maximum number of join attempts per subscribe, and of failed connection
  ///     attempts in a row before the client stops reconnecting. Defaults to ``defaultMaxRetryAttempts``.
  ///   - disconnectOnEmptyChannelsAfter: How long to wait before disconnecting when all channels are removed. Defaults to ``defaultDisconnectOnEmptyChannelsAfter``.
  ///   - logLevel: Optional log level for Realtime log output.
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
    reconnectDelay: Duration = Self.defaultReconnectDelay,
    timeout: Duration = Self.defaultTimeout,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: Duration = Self.defaultDisconnectOnEmptyChannelsAfter,
    logLevel: LogLevel? = nil,
    http: HTTPClientConfiguration = .init(),
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.realtime"),
    session: URLSession? = nil,
    handleAppLifecycle: Bool = Self.defaultHandleAppLifecycle,
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeout = timeout
    self.connectOnSubscribe = connectOnSubscribe
    self.maxRetryAttempts = maxRetryAttempts
    self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
    self.handleAppLifecycle = handleAppLifecycle
    self.logLevel = logLevel
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

/// Describes the subscription state of a ``RealtimeChannel``.
///
/// ## Topics
/// ### States
/// - ``unsubscribed``
/// - ``subscribing``
/// - ``subscribed``
/// - ``unsubscribing``
public struct RealtimeChannelStatus: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``RealtimeChannelStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``RealtimeChannelStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The channel has not yet joined or has left the Realtime topic.
  public static let unsubscribed: RealtimeChannelStatus = "unsubscribed"

  /// The channel is in the process of joining the Realtime topic.
  public static let subscribing: RealtimeChannelStatus = "subscribing"

  /// The channel has successfully joined the Realtime topic and is receiving events.
  public static let subscribed: RealtimeChannelStatus = "subscribed"

  /// The channel is in the process of leaving the Realtime topic.
  public static let unsubscribing: RealtimeChannelStatus = "unsubscribing"
}

/// Describes the connection state of a ``RealtimeClient``.
///
/// ## Topics
/// ### States
/// - ``disconnected``
/// - ``connecting``
/// - ``connected``
public struct RealtimeClientStatus: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public let rawValue: String

  /// Creates a ``RealtimeClientStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``RealtimeClientStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The WebSocket is not connected.
  public static let disconnected: RealtimeClientStatus = "disconnected"

  /// A WebSocket connection attempt is in progress.
  public static let connecting: RealtimeClientStatus = "connecting"

  /// The WebSocket is connected and ready to exchange messages.
  public static let connected: RealtimeClientStatus = "connected"

  public var description: String { rawValue }
}

/// Describes the result of a heartbeat cycle.
///
/// The Realtime client sends periodic heartbeat messages to keep the WebSocket
/// connection alive. Use ``RealtimeClient/heartbeat``
/// to observe heartbeat status changes.
///
/// ## Topics
/// ### States
/// - ``sent``
/// - ``ok``
/// - ``error``
/// - ``timeout``
public struct HeartbeatStatus: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``HeartbeatStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``HeartbeatStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Heartbeat was sent.
  public static let sent: HeartbeatStatus = "sent"

  /// Heartbeat was received and acknowledged by the server.
  public static let ok: HeartbeatStatus = "ok"

  /// Server responded with an error to the heartbeat.
  public static let error: HeartbeatStatus = "error"

  /// Heartbeat was not acknowledged within the configured timeout interval.
  public static let timeout: HeartbeatStatus = "timeout"
}

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// Verbosity of log output emitted by the Realtime client.
///
/// Pass a value to ``RealtimeClientOptions/init(headers:heartbeatInterval:reconnectDelay:timeout:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:logLevel:http:accessToken:logger:session:handleAppLifecycle:clock:)``
/// to control how much detail the Realtime server logs.
///
/// ## Topics
/// ### Levels
/// - ``info``
/// - ``warn``
/// - ``error``
public struct LogLevel: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``LogLevel`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``LogLevel`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Informational messages.
  public static let info: LogLevel = "info"

  /// Warning messages.
  public static let warn: LogLevel = "warn"

  /// Error messages only.
  public static let error: LogLevel = "error"
}
