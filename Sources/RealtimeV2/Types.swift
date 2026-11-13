//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

public import Foundation
package import HTTPTypes

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// Phoenix protocol version used for WebSocket communication.
///
/// The version controls how messages are serialized on the wire between the client
/// and the Realtime server.
///
/// ## Topics
/// ### Protocol Versions
/// - ``v1``
/// - ``v2``
public enum RealtimeProtocolVersion: String, Sendable {
  /// Protocol 1.0.0 — JSON object text frames for all messages.
  case v1 = "1.0.0"

  /// Protocol 2.0.0 — JSON array text frames for non-broadcast messages,
  /// binary frames for broadcast messages.
  case v2 = "2.0.0"
}

/// Options for initializing ``RealtimeClientV2``.
///
/// Use this struct to customize the behavior of the Realtime client, including connection
/// timing, authentication, protocol version, and app lifecycle handling.
///
/// ```swift
/// let options = RealtimeClientOptions(
///   heartbeatInterval: 30,
///   vsn: .v2,
///   handleAppLifecycle: true
/// )
/// let client = RealtimeClientV2(url: realtimeURL, options: options)
/// ```
///
/// ## Topics
/// ### Protocol and Lifecycle
/// - ``vsn``
/// - ``observesAppLifecycle``
/// - ``handleAppLifecycle``
/// ### Default Values
/// - ``defaultHeartbeatInterval``
/// - ``defaultReconnectDelay``
/// - ``defaultTimeoutInterval``
/// - ``defaultDisconnectOnSessionLoss``
/// - ``defaultConnectsOnSubscribe``
/// - ``defaultConnectOnSubscribe``
/// - ``defaultMaxRetryAttempts``
/// - ``defaultDisconnectOnEmptyChannelsAfter``
/// - ``defaultObservesAppLifecycle``
/// - ``defaultHandleAppLifecycle``
/// ### Initialization
/// - ``init(headers:heartbeatInterval:reconnectDelay:timeoutInterval:disconnectOnSessionLoss:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:vsn:logLevel:fetch:accessToken:logger:session:handleAppLifecycle:)``
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPFields
  var heartbeatInterval: TimeInterval
  var reconnectDelay: TimeInterval
  var timeoutInterval: TimeInterval
  var disconnectOnSessionLoss: Bool
  var connectOnSubscribe: Bool
  var maxRetryAttempts: Int
  var disconnectOnEmptyChannelsAfter: TimeInterval

  /// The Phoenix serializer protocol version.
  ///
  /// Defaults to ``RealtimeProtocolVersion/v2``. Use ``RealtimeProtocolVersion/v1`` only
  /// when connecting to a Realtime server that does not support protocol 2.0.0.
  public var vsn: RealtimeProtocolVersion

  /// Whether to automatically handle app lifecycle changes (background/foreground).
  ///
  /// When enabled, the client observes platform lifecycle notifications and — on
  /// foregrounding — reconnects and re-joins any existing channels if the WebSocket
  /// was closed while the app was backgrounded. The client does not proactively
  /// disconnect on backgrounding; short background/foreground cycles keep the
  /// connection alive without churn.
  ///
  /// Disable this to manage the connection yourself with ``RealtimeClientV2/connect()`` and
  /// ``RealtimeClientV2/disconnect(code:reason:)``.
  ///
  /// Default: `true` on iOS, macOS, tvOS, and visionOS. `false` on other platforms
  /// (including watchOS and Linux), where lifecycle observation is not supported.
  public var observesAppLifecycle: Bool

  /// Whether to automatically handle app lifecycle changes (background/foreground).
  @available(*, deprecated, message: "Use observesAppLifecycle instead.")
  public var handleAppLifecycle: Bool {
    get { observesAppLifecycle }
    set { observesAppLifecycle = newValue }
  }

  /// Sets the log level for Realtime
  var logLevel: RealtimeServerLogLevel?
  package var fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))?
  package var accessToken: (@Sendable () async throws -> String?)?
  package var logger: (any SupabaseLogger)?

  /// A template `URLSession` used to configure the Realtime WebSocket connection.
  ///
  /// Realtime never uses this session object directly — it always creates its own dedicated
  /// internal session, copying this session's `configuration` and forwarding its `delegate`'s
  /// auth-challenge callback (if any). Pass the same preconfigured `URLSession` used
  /// elsewhere in your app (e.g. one with a `URLSessionDelegate` implementing certificate
  /// pinning) to apply the same trust evaluation to Realtime's WebSocket connection.
  /// Defaults to `nil` (equivalent to `.default` configuration with no delegate to forward).
  package var session: URLSession?

  /// Opens the client's WebSocket connections. `nil` uses the SDK's `URLSession` stack, with
  /// the `session` you passed to the initializer.
  ///
  /// Set it to use another WebSocket stack. When it is set, `session` is not used for the
  /// socket.
  ///
  /// ```swift
  /// var options = RealtimeClientOptions()
  /// options.webSocketTransport = MyTransport()
  /// ```
  public var webSocketTransport: (any WebSocketTransport)?

  /// Default interval, in seconds, between heartbeat messages sent to keep the connection alive.
  public static let defaultHeartbeatInterval: TimeInterval = 25

  /// Default base delay, in seconds, before attempting to reconnect after a connection drop.
  /// Later automatic attempts back off exponentially (capped at 30s) from this base until
  /// the connection is reestablished.
  public static let defaultReconnectDelay: TimeInterval = 7

  /// Default maximum time, in seconds, to wait for a server reply before treating a request as timed out.
  public static let defaultTimeoutInterval: TimeInterval = 10

  /// Default for whether to disconnect the channel when the session is lost.
  public static let defaultDisconnectOnSessionLoss = true

  /// Default for whether to automatically connect the socket when subscribing to a channel.
  public static let defaultConnectsOnSubscribe: Bool = true

  /// Default for whether to automatically connect the socket when subscribing to a channel.
  @available(*, deprecated, message: "Use defaultConnectsOnSubscribe instead.")
  public static let defaultConnectOnSubscribe: Bool = defaultConnectsOnSubscribe

  /// Default maximum number of subscribe retry attempts before giving up.
  public static let defaultMaxRetryAttempts: Int = 5

  /// Defers the WebSocket disconnect after the last channel is removed, giving a window to reuse
  /// the existing connection when switching channels without a reconnect penalty. Defaults to
  /// `2 × defaultHeartbeatInterval`. Set to 0 for immediate disconnect. If a new channel is
  /// created before the timer fires, the pending disconnect is cancelled.
  public static let defaultDisconnectOnEmptyChannelsAfter: TimeInterval =
    2 * defaultHeartbeatInterval

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

  /// Default value for ``handleAppLifecycle``.
  @available(*, deprecated, message: "Use defaultObservesAppLifecycle instead.")
  public static let defaultHandleAppLifecycle: Bool = defaultObservesAppLifecycle

  /// Creates a new ``RealtimeClientOptions`` with the specified configuration.
  ///
  /// - Parameters:
  ///   - headers: Additional HTTP headers sent with each WebSocket upgrade request.
  ///   - heartbeatInterval: Interval in seconds between heartbeat messages. Defaults to ``defaultHeartbeatInterval``.
  ///   - reconnectDelay: Base delay in seconds before attempting to reconnect after a disconnection; later automatic attempts back off exponentially from this base until reconnected. Defaults to ``defaultReconnectDelay``.
  ///   - timeoutInterval: Maximum time in seconds to wait for a server reply. Defaults to ``defaultTimeoutInterval``.
  ///   - disconnectOnSessionLoss: Whether to disconnect the channel when the authentication session is lost. Defaults to ``defaultDisconnectOnSessionLoss``.
  ///   - connectOnSubscribe: Whether to automatically call ``RealtimeClientV2/connect()`` when subscribing to a channel. Defaults to ``defaultConnectsOnSubscribe``.
  ///   - maxRetryAttempts: Maximum number of subscribe retry attempts. Defaults to ``defaultMaxRetryAttempts``.
  ///   - disconnectOnEmptyChannelsAfter: Seconds to wait before disconnecting when all channels are removed. Defaults to ``defaultDisconnectOnEmptyChannelsAfter``.
  ///   - vsn: The Phoenix protocol version to use. Defaults to ``RealtimeProtocolVersion/v2``.
  ///   - logLevel: Optional log level for Realtime log output.
  ///   - fetch: Optional custom HTTP fetch function used for REST broadcast calls.
  ///   - accessToken: Optional async closure that returns the current access token.
  ///   - logger: Optional logger conforming to `SupabaseLogger`.
  ///   - session: A template `URLSession` to configure the WebSocket connection from. Defaults to `nil`.
  ///   - handleAppLifecycle: Whether to automatically reconnect on app foreground. Defaults to ``defaultObservesAppLifecycle``.
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectsOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    vsn: RealtimeProtocolVersion = .v2,
    logLevel: RealtimeServerLogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil,
    session: URLSession? = nil,
    handleAppLifecycle: Bool = Self.defaultObservesAppLifecycle
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
    self.maxRetryAttempts = maxRetryAttempts
    self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
    self.vsn = vsn
    self.observesAppLifecycle = handleAppLifecycle
    self.logLevel = logLevel
    self.fetch = fetch
    self.accessToken = accessToken
    self.logger = logger
    self.session = session
  }

  /// Backward-compatible initializer preserving the pre-`vsn` signature.
  /// Calls the primary initializer with `vsn: .v2`.
  @_disfavoredOverload
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectsOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    logLevel: RealtimeServerLogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.init(
      headers: headers,
      heartbeatInterval: heartbeatInterval,
      reconnectDelay: reconnectDelay,
      timeoutInterval: timeoutInterval,
      disconnectOnSessionLoss: disconnectOnSessionLoss,
      connectOnSubscribe: connectOnSubscribe,
      maxRetryAttempts: maxRetryAttempts,
      disconnectOnEmptyChannelsAfter: disconnectOnEmptyChannelsAfter,
      vsn: .v2,
      logLevel: logLevel,
      fetch: fetch,
      accessToken: accessToken,
      logger: logger
    )
  }

  var apikey: String? {
    headers[.apiKey]
  }
}

/// A token that represents a Realtime subscription and cancels it on deallocation.
///
/// Store the returned token from subscription methods (e.g. ``RealtimeChannelV2/onBroadcast(event:callback:)``)
/// to keep the subscription alive. When the token is deallocated or ``ObservationToken/cancel()``
/// is called, the underlying callback is removed.
///
/// ```swift
/// let subscription = channel.onBroadcast(event: "message") { payload in
///   print(payload)
/// }
/// defer { subscription.cancel() }
/// ```
@available(
  *, deprecated, message: "Read the matching AsyncStream and cancel its task instead."
)
public typealias RealtimeSubscription = ObservationToken

/// A server event about a ``RealtimeChannelV2``, emitted by ``RealtimeChannelV2/events()``.
///
/// The set of cases is fixed until the next major version, so a `switch` needs no `default`.
///
/// ## Topics
/// ### Events
/// - ``resubscribed``
/// - ``postgresChangesReady``
/// - ``postgresChangesFailed(_:)``
/// - ``replicationReady``
/// - ``replicationFailed(_:)``
public enum RealtimeChannelEvent: Hashable, Sendable {
  /// The channel joined again after it was subscribed, for example after a reconnect. Events
  /// sent while it was away were missed; reload any state built from them.
  case resubscribed

  /// The server set up the channel's Postgres changes subscriptions ("Subscribed to
  /// PostgreSQL"). Changes from now on are delivered.
  case postgresChangesReady

  /// The server could not set up the channel's Postgres changes subscriptions. The value is the
  /// server's message.
  case postgresChangesFailed(String)

  /// The Postgres replication connection behind the channel is ready ("Replication connection
  /// established"). The server sends it only when you opt in with
  /// ``BroadcastJoinConfig/waitsForReplication``.
  case replicationReady

  /// The server reported a `system` error on the channel. The value is the server's message.
  ///
  /// The name is the v3 name, but the server uses this message for more than replication: it
  /// sends it whenever it shuts the channel down, for example for a rate limit ("Too many
  /// messages per second"), a token it no longer accepts, or a database error. A replication
  /// connection that is not ready in time is one of these cases. Read the message to tell them
  /// apart.
  case replicationFailed(String)
}

extension RealtimeChannelEvent {
  /// Reads a `system` message. `nil` for a message that is not about Postgres changes or
  /// replication, or that has no `ok` or `error` status.
  init?(systemMessage message: RealtimeMessageV2) {
    let `extension` = message.payload["extension"]?.stringValue
    let reason = message.payload["message"]?.stringValue ?? "\(message.payload)"
    switch (`extension`, message.status) {
    case (ChannelEvent.postgresChanges, .ok): self = .postgresChangesReady
    case (ChannelEvent.postgresChanges, .error): self = .postgresChangesFailed(reason)
    case (ChannelEvent.system, .ok): self = .replicationReady
    case (ChannelEvent.system, .error): self = .replicationFailed(reason)
    default: return nil
    }
  }
}

/// Describes the subscription state of a ``RealtimeChannelV2``.
///
/// ## Topics
/// ### States
/// - ``unsubscribed``
/// - ``subscribing``
/// - ``subscribed``
/// - ``unsubscribing``
public enum RealtimeChannelStatus: Sendable {
  /// The channel has not yet joined or has left the Realtime topic.
  case unsubscribed

  /// The channel is in the process of joining the Realtime topic.
  case subscribing

  /// The channel has successfully joined the Realtime topic and is receiving events.
  case subscribed

  /// The channel is in the process of leaving the Realtime topic.
  case unsubscribing
}

/// Describes the connection state of a ``RealtimeClientV2``.
///
/// ## Topics
/// ### States
/// - ``disconnected``
/// - ``connecting``
/// - ``connected``
public enum RealtimeClientStatus: Sendable, CustomStringConvertible {
  /// The WebSocket is not connected.
  case disconnected

  /// A WebSocket connection attempt is in progress.
  case connecting

  /// The WebSocket is connected and ready to exchange messages.
  case connected

  public var description: String {
    switch self {
    case .disconnected: "Disconnected"
    case .connecting: "Connecting"
    case .connected: "Connected"
    }
  }
}

/// One step of the heartbeat cycle, emitted by ``RealtimeClientV2/heartbeats()``.
///
/// The client sends a heartbeat at each heartbeat interval. When the next one is due and the
/// server has not acknowledged the previous one, the client reports ``timedOut`` and reconnects.
///
/// ## Topics
/// ### Events
/// - ``sent``
/// - ``acknowledged(latency:)``
/// - ``timedOut``
public enum HeartbeatEvent: Hashable, Sendable {
  /// The client sent a heartbeat.
  case sent

  /// The server acknowledged the heartbeat `latency` after it was sent.
  case acknowledged(latency: Duration)

  /// The server did not acknowledge the previous heartbeat in time. The client drops the
  /// socket and reconnects.
  case timedOut
}

/// Describes the result of a heartbeat cycle.
///
/// The Realtime client sends periodic heartbeat messages to keep the WebSocket
/// connection alive.
///
/// ## Topics
/// ### States
/// - ``sent``
/// - ``ok``
/// - ``error``
/// - ``timeout``
/// - ``disconnected``
@available(*, deprecated, message: "Use HeartbeatEvent instead.")
public enum HeartbeatStatus: Sendable {
  /// Heartbeat was sent.
  case sent

  /// Heartbeat was received and acknowledged by the server.
  case ok

  /// Server responded with an error to the heartbeat.
  case error

  /// Heartbeat was not acknowledged within the configured timeout interval.
  case timeout

  /// Socket is disconnected; no heartbeat can be sent.
  case disconnected
}

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// How much the Realtime server logs for one connection.
///
/// Pass a value to ``RealtimeClientOptions/init(headers:heartbeatInterval:reconnectDelay:timeoutInterval:disconnectOnSessionLoss:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:vsn:logLevel:fetch:accessToken:logger:session:handleAppLifecycle:)``
/// to control how much detail the Realtime server logs.
///
/// ## Topics
/// ### Levels
/// - ``info``
/// - ``warn``
/// - ``error``
public enum RealtimeServerLogLevel: String, Sendable {
  /// Informational messages.
  case info

  /// Warning messages.
  case warn

  /// Error messages only.
  case error

  /// Warnings and errors. The same level as ``warn``, with the name v3 uses.
  public static var warning: Self { .warn }
}

/// The v2 name of ``RealtimeServerLogLevel``.
@available(*, deprecated, renamed: "RealtimeServerLogLevel")
public typealias LogLevel = RealtimeServerLogLevel

extension RealtimeClientStatus {
  /// Whether the client is ``connected``.
  public var isConnected: Bool {
    self == .connected
  }
}

extension RealtimeChannelStatus {
  /// Whether the channel is ``subscribed``.
  public var isSubscribed: Bool {
    self == .subscribed
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
  }
}
