//
//  RealtimeClient.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
public import Foundation
import HTTPTypes
import Helpers
import IssueReporting

/// The Realtime socket and its channels.
///
/// One client owns one WebSocket. Channels share it, and the client reconnects and rejoins them
/// after a drop.
///
/// Keep the client for as long as you use its channels. Releasing it closes the socket and
/// finishes every stream of the client and its channels, and a channel handle that outlives it
/// stays unsubscribed.
public final class RealtimeClient: Sendable {
  let engine: RealtimeEngine
  private let rest: RealtimeREST
  private let channelsByTopic = LockIsolated<[String: RealtimeChannel]>([:])
  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    private let lifecycleObserver: RealtimeLifecycleObserver?
  #endif

  /// Creates a client. It does not connect until ``connect()`` or the first
  /// ``RealtimeChannel/subscribe()``.
  ///
  /// - Parameters:
  ///   - url: The Realtime endpoint, such as `https://<project>.supabase.co/realtime/v1`.
  ///   - options: How the client connects, retries and authenticates.
  public init(url: URL, options: RealtimeClientOptions = .init()) {
    let configuration = Self.engineConfiguration(url: url, options: options)
    var transport = options.webSocketTransport ?? URLSessionWebSocketTransport()
    if var urlSession = transport as? URLSessionWebSocketTransport {
      urlSession.maximumMessageSize = options.maximumMessageSize
      transport = urlSession
    }
    let engine = RealtimeEngine(
      configuration: configuration, transport: transport, clock: options.clock)
    self.engine = engine
    let apikey = options.headers[.apikey]
    let accessToken = options.accessToken
    rest = RealtimeREST(
      baseURL: url, apikey: apikey, http: options.http, timeout: options.timeout,
      clock: options.clock,
      accessToken: {
        guard let accessToken else { return engine.accessToken ?? apikey }
        if let token = try await accessToken() { return token }
        return engine.accessToken
      })
    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      lifecycleObserver =
        options.handleAppLifecycle ? RealtimeLifecycleObserver(engine: engine) : nil
    #endif
  }

  deinit {
    engine.shutdown()
  }

  static func engineConfiguration(url: URL, options: RealtimeClientOptions)
    -> RealtimeEngineConfiguration
  {
    var configuration = RealtimeEngineConfiguration(
      url: RealtimeURL.webSocket(
        baseURL: url, apikey: options.headers[.apikey],
        logLevel: options.serverLogLevel?.rawValue))
    configuration.headers = options.headers
    if configuration.headers[.xClientInfo] == nil {
      configuration.headers[.xClientInfo] = "realtime-swift/\(version)"
    }
    configuration.heartbeatInterval = options.heartbeatInterval
    configuration.heartbeatTimeout = options.heartbeatTimeout
    configuration.timeout = options.timeout
    configuration.connectOnSubscribe = options.connectOnSubscribe
    configuration.connection.reconnect = options.reconnect
    configuration.connection.idleDisconnectAfter = options.disconnectOnEmptyChannelsAfter
    configuration.channel.rejoin = options.rejoin
    configuration.accessToken = options.accessToken
    if let authorization = options.headers[.authorization],
      authorization.lowercased().hasPrefix("bearer ")
    {
      configuration.initialAccessToken = String(authorization.dropFirst("bearer ".count))
    }
    configuration.logger = options.logger
    return configuration
  }

  // MARK: - Status

  /// The socket's status, read without waiting.
  public var status: RealtimeConnectionStatus {
    engine.connectionStatus
  }

  /// The socket's status, starting with the current one. Only the newest status is buffered.
  public var statusChanges: RealtimeStream<RealtimeConnectionStatus> {
    RealtimeStream(engine.connectionStatuses())
  }

  /// Every heartbeat the client sends, and its outcome.
  public var heartbeats: RealtimeStream<HeartbeatEvent> {
    RealtimeStream(engine.heartbeats())
  }

  // MARK: - Connection

  /// Opens the socket and returns once it is connected. Returns at once when it already is.
  ///
  /// A transient failure does not throw: the client retries with
  /// ``RealtimeClientOptions/reconnect`` and reports it on ``statusChanges``.
  ///
  /// - Throws: ``RealtimeError`` when the server refuses the upgrade for good (a 401 or 403 is
  ///   ``RealtimeError/Kind/unauthorized``), of kind ``RealtimeError/Kind/notConnected`` when
  ///   ``disconnect()`` runs first, or `CancellationError` when the calling task is cancelled.
  ///   Cancelling does not stop the client from connecting.
  public func connect() async throws {
    try await engine.connect()
  }

  /// Leaves every channel, closes the socket, and returns once it is closed. The channels stay
  /// on the client; subscribe them again after the next ``connect()``.
  public func disconnect() async {
    await engine.disconnect()
  }

  /// Closes the socket and keeps every channel wanting its subscription, for ``resume()``.
  public func pause() async {
    await engine.pause()
  }

  /// Reconnects after ``pause()`` and rejoins every channel that was subscribed.
  public func resume() async {
    await engine.resume()
  }

  // MARK: - Channels

  /// The channel for `topic`, made on the first call. Later calls return the same instance.
  ///
  /// A later call with a different configuration reports an issue and returns the existing
  /// channel unchanged. Remove the channel first to change its configuration.
  ///
  /// - Parameters:
  ///   - topic: The channel name, without the `realtime:` prefix.
  ///   - configure: Sets the channel's options on a new channel.
  public func channel(
    _ topic: String,
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) -> RealtimeChannel {
    var configuration = RealtimeChannelConfiguration()
    configure(&configuration)
    let channel = channelsByTopic.withValue { [configuration] channels in
      if let existing = channels[topic] { return existing }
      let channel = RealtimeChannel(
        topic: topic, configuration: configuration, engine: engine, rest: rest)
      channels[topic] = channel
      return channel
    }
    if channel.configuration != configuration {
      reportIssue(
        "channel(\"\(topic)\") was called with a different configuration than the existing "
          + "channel. Remove the channel first to change its configuration.")
    }
    return channel
  }

  /// Every channel the client has, sorted by topic.
  public var channels: [RealtimeChannel] {
    channelsByTopic.value.values.sorted { $0.topic < $1.topic }
  }

  /// Leaves `channel` and removes it from the client. Its streams finish.
  ///
  /// Does nothing for a channel that is not this client's current one for its topic: one already
  /// removed, or one from another client. A removed channel cannot subscribe again; get a new one
  /// from ``channel(_:configure:)``.
  ///
  /// The socket closes ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter`` after the last
  /// channel is removed.
  public func removeChannel(_ channel: RealtimeChannel) async {
    let isCurrent = channelsByTopic.withValue { channels in
      guard channels[channel.topic] === channel else { return false }
      channels[channel.topic] = nil
      // Under the lock, so a new handle for the topic always finds this one retired.
      channel.owner.retire()
      return true
    }
    guard isCurrent else { return }
    await engine.removeChannel(channel.wireTopic, owner: channel.owner)
  }

  /// Leaves and removes every channel.
  public func removeAllChannels() async {
    let channels = channelsByTopic.withValue { channels in
      defer { channels = [:] }
      for channel in channels.values { channel.owner.retire() }
      return Array(channels.values)
    }
    await withTaskGroup(of: Void.self) { group in
      for channel in channels {
        group.addTask { [engine] in
          await engine.removeChannel(channel.wireTopic, owner: channel.owner)
        }
      }
    }
  }

  // MARK: - Auth

  /// Sets the token channels join with and sends it to every joined channel.
  ///
  /// The token stays until the next call or the next result of
  /// ``RealtimeClientOptions/accessToken``. `nil` asks that provider again; without a provider,
  /// `nil` keeps the current token.
  public func setAuth(_ accessToken: String?) async {
    await engine.setAuth(accessToken)
  }
}
