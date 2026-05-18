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
/// - ``handleAppLifecycle``
/// ### Default Values
/// - ``defaultHeartbeatInterval``
/// - ``defaultReconnectDelay``
/// - ``defaultTimeoutInterval``
/// - ``defaultDisconnectOnSessionLoss``
/// - ``defaultConnectOnSubscribe``
/// - ``defaultMaxRetryAttempts``
/// - ``defaultDisconnectOnEmptyChannelsAfter``
/// - ``defaultHandleAppLifecycle``
/// ### Initialization
/// - ``init(headers:heartbeatInterval:reconnectDelay:timeoutInterval:disconnectOnSessionLoss:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:vsn:logLevel:fetch:accessToken:logger:handleAppLifecycle:)``
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
  public var handleAppLifecycle: Bool

  /// Sets the log level for Realtime
  var logLevel: LogLevel?
  package var fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))?
  package var accessToken: (@Sendable () async throws -> String?)?
  package var logger: (any SupabaseLogger)?

  /// Optional handler for evaluating server trust on WebSocket connections.
  /// Use this to implement certificate pinning for Realtime WebSocket connections.
  /// The handler receives the URLSession, the authentication challenge, and a completion handler
  /// that must be called with the disposition and optional credential.
  public var serverTrustHandler: (
    @Sendable (
      _ session: URLSession,
      _ challenge: URLAuthenticationChallenge,
      _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Void
  )?

  /// Default interval, in seconds, between heartbeat messages sent to keep the connection alive.
  public static let defaultHeartbeatInterval: TimeInterval = 25

  /// Default delay, in seconds, before attempting to reconnect after a connection drop.
  public static let defaultReconnectDelay: TimeInterval = 7

  /// Default maximum time, in seconds, to wait for a server reply before treating a request as timed out.
  public static let defaultTimeoutInterval: TimeInterval = 10

  /// Default for whether to disconnect the channel when the session is lost.
  public static let defaultDisconnectOnSessionLoss = true

  /// Default for whether to automatically connect the socket when subscribing to a channel.
  public static let defaultConnectOnSubscribe: Bool = true

  /// Default maximum number of subscribe retry attempts before giving up.
  public static let defaultMaxRetryAttempts: Int = 5

  /// Defers the WebSocket disconnect after the last channel is removed, giving a window to reuse
  /// the existing connection when switching channels without a reconnect penalty. Defaults to
  /// `2 × defaultHeartbeatInterval`. Set to 0 for immediate disconnect. If a new channel is
  /// created before the timer fires, the pending disconnect is cancelled.
  public static let defaultDisconnectOnEmptyChannelsAfter: TimeInterval =
    2 * defaultHeartbeatInterval

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
  ///   - heartbeatInterval: Interval in seconds between heartbeat messages. Defaults to ``defaultHeartbeatInterval``.
  ///   - reconnectDelay: Delay in seconds before attempting to reconnect after a disconnection. Defaults to ``defaultReconnectDelay``.
  ///   - timeoutInterval: Maximum time in seconds to wait for a server reply. Defaults to ``defaultTimeoutInterval``.
  ///   - disconnectOnSessionLoss: Whether to disconnect the channel when the authentication session is lost. Defaults to ``defaultDisconnectOnSessionLoss``.
  ///   - connectOnSubscribe: Whether to automatically call ``RealtimeClientV2/connect()`` when subscribing to a channel. Defaults to ``defaultConnectOnSubscribe``.
  ///   - maxRetryAttempts: Maximum number of subscribe retry attempts. Defaults to ``defaultMaxRetryAttempts``.
  ///   - disconnectOnEmptyChannelsAfter: Seconds to wait before disconnecting when all channels are removed. Defaults to ``defaultDisconnectOnEmptyChannelsAfter``.
  ///   - vsn: The Phoenix protocol version to use. Defaults to ``RealtimeProtocolVersion/v2``.
  ///   - logLevel: Optional log level for Realtime log output.
  ///   - fetch: Optional custom HTTP fetch function used for REST broadcast calls.
  ///   - accessToken: Optional async closure that returns the current access token.
  ///   - logger: Optional logger conforming to `SupabaseLogger`.
  ///   - handleAppLifecycle: Whether to automatically reconnect on app foreground. Defaults to ``defaultHandleAppLifecycle``.
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    vsn: RealtimeProtocolVersion = .v2,
    logLevel: LogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil,
    handleAppLifecycle: Bool = Self.defaultHandleAppLifecycle,
    serverTrustHandler: (
      @Sendable (
        _ session: URLSession,
        _ challenge: URLAuthenticationChallenge,
        _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) -> Void
    )? = nil
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
    self.handleAppLifecycle = handleAppLifecycle
    self.logLevel = logLevel
    self.fetch = fetch
    self.accessToken = accessToken
    self.logger = logger
    self.serverTrustHandler = serverTrustHandler
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
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    logLevel: LogLevel? = nil,
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
public typealias RealtimeSubscription = ObservationToken

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

/// Describes the result of a heartbeat cycle.
///
/// The Realtime client sends periodic heartbeat messages to keep the WebSocket
/// connection alive. Use ``RealtimeClientV2/heartbeat`` or ``RealtimeClientV2/onHeartbeat(_:)``
/// to observe heartbeat status changes.
///
/// ## Topics
/// ### States
/// - ``sent``
/// - ``ok``
/// - ``error``
/// - ``timeout``
/// - ``disconnected``
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

/// Verbosity of log output emitted by the Realtime client.
///
/// Pass a value to ``RealtimeClientOptions/init(headers:heartbeatInterval:reconnectDelay:timeoutInterval:disconnectOnSessionLoss:connectOnSubscribe:maxRetryAttempts:disconnectOnEmptyChannelsAfter:vsn:logLevel:fetch:accessToken:logger:handleAppLifecycle:)``
/// to control how much detail the Realtime server logs.
///
/// ## Topics
/// ### Levels
/// - ``info``
/// - ``warn``
/// - ``error``
public enum LogLevel: String, Sendable {
  /// Informational messages.
  case info

  /// Warning messages.
  case warn

  /// Error messages only.
  case error
}
