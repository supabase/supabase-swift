//
//  RealtimeClientOptions.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

public import HTTPTypes
public import Helpers
public import Logging

/// How a ``RealtimeClient`` connects, retries and authenticates.
public struct RealtimeClientOptions: Sendable {
  /// Header fields for the WebSocket upgrade. The `apikey` field also goes into the WebSocket URL
  /// and onto the REST broadcast requests. An `Authorization: Bearer <token>` field gives the first
  /// token channels join with, until ``accessToken`` or ``RealtimeClient/setAuth(_:)`` gives
  /// another. The client adds `X-Client-Info` when it is missing.
  public var headers: HTTPFields = [:]
  /// How often the client sends a heartbeat.
  public var heartbeatInterval: Duration = .seconds(25)
  /// How long the client waits for a heartbeat reply before it drops the socket and reconnects.
  public var heartbeatTimeout: Duration = .seconds(10)
  /// How long a join, a leave, an acknowledged push or a REST broadcast waits for its reply. It
  /// does not bound the WebSocket connect, which has its own 15-second limit.
  public var timeout: Duration = .seconds(15)
  /// The wait before each reconnect after the socket drops.
  public var reconnect: BackoffPolicy = .fullJitter(base: .seconds(1), cap: .seconds(30))
  /// The wait before each rejoin after the server drops a channel.
  public var rejoin: BackoffPolicy = .steps([.seconds(1), .seconds(2), .seconds(5), .seconds(10)])
  /// Whether ``RealtimeChannel/subscribe()`` connects the socket when it is closed.
  public var connectOnSubscribe = true
  /// How long the socket stays open after the last channel is removed.
  public var disconnectOnEmptyChannelsAfter: Duration = .seconds(50)
  /// Whether the client checks the socket when the app comes back to the foreground. Apple
  /// platforms only. The client never disconnects when the app goes to the background.
  public var handleAppLifecycle = true
  /// The largest frame, in bytes, the default transport receives. The server never sends a frame
  /// over 5,000,000 bytes. It also applies when ``webSocketTransport`` is a
  /// ``URLSessionWebSocketTransport``; any other transport ignores it.
  public var maximumMessageSize = 5_000_000
  /// How much the server logs about this socket, or `nil` for the server's default.
  public var serverLogLevel: RealtimeServerLogLevel?
  /// The WebSocket stack, or `nil` for ``URLSessionWebSocketTransport``.
  public var webSocketTransport: (any WebSocketTransport)?
  /// The HTTP stack for REST broadcasts.
  public var http: HTTPClientConfiguration = .init()
  /// Returns the token to join channels with. The client calls it before each connect and
  /// again before the token expires. A token from ``RealtimeClient/setAuth(_:)`` stays until the
  /// next result.
  public var accessToken: (@Sendable () async throws -> String?)?
  /// Where the client logs.
  public var logger: Logger = supabaseDefaultLogger(label: "io.supabase.realtime")
  /// The clock for heartbeats, timeouts and retries.
  public var clock: any Clock<Duration> = ContinuousClock()

  /// Creates the default options.
  public init() {}
}
