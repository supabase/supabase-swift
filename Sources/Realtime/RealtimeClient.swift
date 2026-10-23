//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
import Logging
import Phoenix

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A client for Supabase Realtime: one WebSocket connection and the channels on it.
///
/// Create channels with ``channel(_:options:)``, open their streams, then call
/// ``RealtimeChannel/subscribeWithError()``. The client connects on the first subscribe unless
/// ``RealtimeClientOptions`` turns `connectOnSubscribe` off.
///
/// ```swift
/// let client = RealtimeClient(url: realtimeURL, options: RealtimeClientOptions(headers: ["apikey": key]))
/// let channel = client.channel("room:lobby")
/// let messages = channel.broadcastStream(event: "message")
/// try await channel.subscribeWithError()
/// ```
///
/// ## Topics
/// ### Connection
/// - ``status``
/// - ``statusChange``
/// - ``heartbeat``
/// - ``connect()``
/// - ``disconnect(code:reason:)``
/// ### Channels
/// - ``channels``
/// - ``channel(_:options:)``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
/// ### Authentication
/// - ``setAuth(_:)``
public final class RealtimeClient: Sendable {
  let connection: RealtimeConnection
  var options: RealtimeClientOptions { connection.options }
  var url: URL { connection.url }
  private let state = LockIsolated(State())
  /// Asks `RealtimeClientOptions.accessToken` at every heartbeat, as supabase-js does, so a
  /// third-party token reaches the channels before it expires.
  private let tokenRefresh = LockIsolated<Task<Void, Never>?>(nil)
  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    private let lifecycle = LockIsolated<RealtimeLifecycleManager?>(nil)
  #endif

  private struct State {
    var channels: [String: RealtimeChannel] = [:]
    var idleDisconnect: Task<Void, Never>?
    var wasConnectedBeforeBackground = false

    mutating func cancelIdleDisconnect() {
      idleDisconnect?.cancel()
      idleDisconnect = nil
    }
  }

  /// Creates a client for the Realtime server at `url`, such as
  /// `https://<project>.supabase.co/realtime/v1`.
  public convenience init(url: URL, options: RealtimeClientOptions) {
    let headers = Dictionary(
      options.headers.map { ($0.name.rawName, $0.value) }, uniquingKeysWith: { _, last in last })
    self.init(
      url: url,
      options: options,
      transport: URLSessionTransport(
        configuration: { options.session?.configuration ?? .default },
        headers: headers,
        delegate: options.session?.delegate
      )
    )
  }

  init(url: URL, options: RealtimeClientOptions, transport: any Transport) {
    connection = RealtimeConnection(url: url, options: options, transport: transport)
    if options.accessToken != nil {
      let heartbeats = connection.socket.heartbeats
      tokenRefresh.setValue(
        Task { [weak self] in
          for await heartbeat in heartbeats where heartbeat == .sent {
            await self?.setAuth()
          }
        })
    }
    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      if options.handleAppLifecycle {
        lifecycle.setValue(RealtimeLifecycleManager(client: self))
      }
    #endif
  }

  deinit {
    tokenRefresh.value?.cancel()
  }

  /// The connection status.
  public var status: RealtimeClientStatus {
    RealtimeClientStatus(connection.socket.status)
  }

  /// The current status first, then every change.
  ///
  /// Reconnect waits show as ``RealtimeClientStatus/connecting``. Cancel the task that reads the
  /// stream to stop it.
  public var statusChange: AsyncStream<RealtimeClientStatus> {
    connection.socket.statuses.forwarding(removingDuplicates: true, RealtimeClientStatus.init)
  }

  /// Every heartbeat step from now on: ``HeartbeatStatus/sent``, then ``HeartbeatStatus/ok``,
  /// ``HeartbeatStatus/error``, or ``HeartbeatStatus/timeout``.
  public var heartbeat: AsyncStream<HeartbeatStatus> {
    connection.socket.heartbeats.forwarding(removingDuplicates: false, HeartbeatStatus.init)
  }

  /// Connects and returns once the WebSocket is open. Does nothing when it already is.
  ///
  /// Channels that want to be subscribed join on their own once the socket opens.
  ///
  /// - Throws: ``RealtimeError`` when the client stops reconnecting: kind `.transport` for a
  ///   handshake the server refused, such as HTTP 401 for a bad API key, or a close code of
  ///   4000 or above, and kind `.notConnected` when ``disconnect(code:reason:)`` ran first.
  ///   `CancellationError` when the calling task is cancelled.
  public func connect() async throws {
    try await connection.connect()
  }

  /// Closes the connection and stops reconnecting.
  ///
  /// Channels keep their subscription: they show ``RealtimeChannelStatus/subscribing`` and join
  /// again on the next ``connect()``. Call ``removeAllChannels()`` to leave them first.
  ///
  /// - Parameters:
  ///   - code: The WebSocket close code. Codes other than 1000 and 3000 to 4999 go out as 1000.
  ///   - reason: The close reason.
  public func disconnect(code: Int? = nil, reason: String? = nil) async {
    state.withValue {
      $0.cancelIdleDisconnect()
      $0.wasConnectedBeforeBackground = false
    }
    await connection.socket.disconnect(code: code ?? 1000, reason: reason)
  }

  /// The channels of this client, keyed by their topic, `realtime:<name>`.
  public var channels: [String: RealtimeChannel] {
    state.value.channels
  }

  /// Returns the channel for `topic`, creating it on first use.
  ///
  /// A second call with the same topic returns the same channel and ignores `options`.
  ///
  /// - Parameters:
  ///   - topic: The channel name, without the `realtime:` prefix.
  ///   - options: Sets the broadcast, presence, and privacy options of a new channel.
  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    let realtimeTopic = "realtime:\(topic)"
    let existing = state.withValue {
      $0.cancelIdleDisconnect()
      return $0.channels[realtimeTopic]
    }
    if let existing {
      return existing
    }
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(), presence: PresenceJoinConfig(), isPrivate: false)
    options(&config)
    let channel = RealtimeChannel(topic: realtimeTopic, config: config, connection: connection)
    return state.withValue {
      $0.cancelIdleDisconnect()
      if let raced = $0.channels[realtimeTopic] {
        return raced
      }
      $0.channels[realtimeTopic] = channel
      return channel
    }
  }

  /// Unsubscribes `channel`, ends its streams, and removes it from this client.
  ///
  /// When no channel is left, the client disconnects after
  /// `RealtimeClientOptions.disconnectOnEmptyChannelsAfter`, unless a new channel comes first.
  public func removeChannel(_ channel: RealtimeChannel) async {
    state.withValue {
      if $0.channels[channel.topic] === channel {
        $0.channels[channel.topic] = nil
      }
    }
    await channel.remove()
    if state.value.channels.isEmpty {
      await disconnectWhenIdle()
    }
  }

  /// Unsubscribes and removes every channel, then disconnects.
  public func removeAllChannels() async {
    let removed = state.withValue { state in
      defer { state.channels = [:] }
      return Array(state.channels.values)
    }
    await withTaskGroup(of: Void.self) { group in
      for channel in removed {
        group.addTask { await channel.remove() }
      }
    }
    await disconnect()
  }

  private func disconnectWhenIdle() async {
    let delay = connection.options.disconnectOnEmptyChannelsAfter
    guard delay > .zero else {
      await disconnect()
      return
    }
    let clock = connection.options.clock
    let task = Task { [weak self] in
      do {
        try await clock.sleep(for: delay)
      } catch {
        return
      }
      guard let self, self.state.withValue({ $0.channels.isEmpty && !Task.isCancelled }) else {
        return
      }
      await self.disconnect()
    }
    let armed = state.withValue {
      $0.idleDisconnect?.cancel()
      $0.idleDisconnect = $0.channels.isEmpty ? task : nil
      return $0.idleDisconnect != nil
    }
    if !armed {
      task.cancel()
    }
  }

  /// Sets the access token that channels send to authorize Realtime and its RLS checks.
  ///
  /// Every subscribed channel gets the new token at once. A channel that joins later sends it in
  /// its join. With no `token`, the client asks `RealtimeClientOptions.accessToken`.
  public func setAuth(_ token: String? = nil) async {
    let newToken: String?
    do {
      if let token {
        newToken = token
      } else {
        newToken = try await connection.options.accessToken?()
      }
    } catch {
      connection.options.logger.error("Failed to fetch access token: \(error)")
      return
    }
    connection.token.setValue(newToken)
    let isChanged = connection.pushedToken.withValue { pushed in
      defer { pushed = newToken }
      return pushed != newToken
    }
    guard isChanged else { return }
    let channels = state.withValue { Array($0.channels.values) }
    await withTaskGroup(of: Void.self) { group in
      for channel in channels {
        group.addTask { await channel.sendAccessToken(newToken) }
      }
    }
  }

  func handleAppBackground() {
    let isConnected = status == .connected
    state.withValue { $0.wasConnectedBeforeBackground = isConnected }
  }

  func handleAppForeground() async {
    let wasConnected = state.withValue { state in
      defer { state.wasConnectedBeforeBackground = false }
      return state.wasConnectedBeforeBackground
    }
    guard wasConnected, status == .disconnected else { return }
    try? await connect()
  }
}
