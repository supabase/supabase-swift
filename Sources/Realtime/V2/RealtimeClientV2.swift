//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking

  let NSEC_PER_SEC: UInt64 = 1000000000
#endif

public actor RealtimeClientV2 {
  public struct Configuration: Sendable {
    var url: URL
    var apiKey: String
    var headers: [String: String]
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var timeoutInterval: TimeInterval
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool
    var logger: (any SupabaseLogger)?

    public init(
      url: URL,
      apiKey: String,
      headers: [String: String] = [:],
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      timeoutInterval: TimeInterval = 10,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true,
      logger: (any SupabaseLogger)? = nil
    ) {
      self.url = url
      self.apiKey = apiKey
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.timeoutInterval = timeoutInterval
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
      self.logger = logger
    }
  }

  public enum Status: Sendable {
    case disconnected
    case connecting
    case connected
  }

  var accessToken: String?
  var ref = 0
  var pendingHeartbeatRef: Int?
  var heartbeatTask: Task<Void, Never>?
  var messageTask: Task<Void, Never>?
  var inFlightConnectionTask: Task<Void, Never>?

  public private(set) var subscriptions: [String: RealtimeChannelV2] = [:]

  let config: Configuration
  lazy var ws: WebSocketClient = {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.httpAdditionalHeaders = config.headers
    return DefaultWebSocketClient(
      realtimeURL: realtimeBaseURL,
      configuration: sessionConfiguration,
      logger: config.logger
    )
  }()

  private let statusStream = SharedStream<Status>(initialElement: .disconnected)

  public var statusChange: AsyncStream<Status> {
    statusStream.makeStream()
  }

  public private(set) var status: Status {
    get { statusStream.lastElement }
    set { statusStream.yield(newValue) }
  }

  deinit {
    heartbeatTask?.cancel()
    messageTask?.cancel()
    subscriptions = [:]
  }

  public init(config: Configuration) {
    self.config = config
    if let customJWT = config.headers["Authorization"]?.split(separator: " ").last {
      accessToken = String(customJWT)
    } else {
      accessToken = config.apiKey
    }
  }

  public func connect() async {
    guard status != .connected else {
      return
    }

    if status == .connecting {

    }

    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if let inFlightConnectionTask {
      return await inFlightConnectionTask.value
    }

    inFlightConnectionTask = Task { [self] in
      defer { inFlightConnectionTask = nil }
      if reconnect {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

        if Task.isCancelled {
          config.logger?.debug("reconnect cancelled, returning")
          return
        }
      }

      if status == .connected {
        config.logger?.debug("Websocket already connected")
        return
      }

      status = .connecting

      ws.connect()

      for await connectionStatus in ws.status {
        switch connectionStatus {
        case .open:
          status = .connected
          config.logger?.debug("Connected to realtime WebSocket")
          listenForMessages()
          startHeartbeating()
          if reconnect {
            await rejoinChannels()
          }

        case .close, .complete:
          config.logger?.debug(
            "Error while trying to connect to realtime WebSocket. Trying again in \(config.reconnectDelay) seconds."
          )
          disconnect()
          await connect(reconnect: true)
        }
      }
    }

    await inFlightConnectionTask?.value
  }

  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannelV2 {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "")
    )
    options(&config)

    return RealtimeChannelV2(
      topic: "realtime:\(topic)",
      config: config,
      socket: self,
      logger: self.config.logger
    )
  }

  public func addChannel(_ channel: RealtimeChannelV2) {
    subscriptions[channel.topic] = channel
  }

  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if await channel.status == .subscribed {
      await channel.unsubscribe()
    }

    subscriptions[channel.topic] = nil

    if subscriptions.isEmpty {
      config.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  private func rejoinChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in subscriptions.values {
        _ = group.addTaskUnlessCancelled {
          await channel.subscribe()
        }

        await group.waitForAll()
      }
    }
  }

  private func listenForMessages() {
    messageTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await message in await ws.receive() {
          await onMessage(message)
        }
      } catch {
        config.logger?.debug(
          "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
        )
        await disconnect()
        await connect(reconnect: true)
      }
    }
  }

  private func startHeartbeating() {
    heartbeatTask = Task { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.heartbeatInterval))
        if Task.isCancelled {
          break
        }
        await sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async {
    if pendingHeartbeatRef != nil {
      pendingHeartbeatRef = nil
      config.logger?.debug("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      disconnect()
      await connect(reconnect: true)
      return
    }

    pendingHeartbeatRef = makeRef()

    await send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: pendingHeartbeatRef?.description,
        topic: "phoenix",
        event: "heartbeat",
        payload: [:]
      )
    )
  }

  public func disconnect() {
    config.logger?.debug("Closing websocket connection")
    ref = 0
    messageTask?.cancel()
    heartbeatTask?.cancel()
    ws.cancel()
    status = .disconnected
  }

  public func setAuth(_ token: String?) async {
    accessToken = token

    for channel in subscriptions.values {
      if let token, await channel.status == .subscribed {
        await channel.updateAuth(jwt: token)
      }
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    let channel = subscriptions[message.topic]

    if let ref = message.ref, Int(ref) == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      config.logger?.debug("heartbeat received")
    } else {
      config.logger?
        .debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      await channel?.onMessage(message)
    }
  }

  func send(_ message: RealtimeMessageV2) async {
    do {
      try await ws.send(message)
    } catch {
      config.logger?.debug("""
      Failed to send message:
      \(message)

      Error:
      \(error)
      """)
    }
  }

  func makeRef() -> Int {
    ref += 1
    return ref
  }

  private var realtimeBaseURL: URL {
    guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
      return config.url
    }

    if components.scheme == "https" {
      components.scheme = "wss"
    } else if components.scheme == "http" {
      components.scheme = "ws"
    }

    guard let url = components.url else {
      return config.url
    }

    return url
  }

  private var realtimeWebSocketURL: URL {
    guard var components = URLComponents(url: realtimeBaseURL, resolvingAgainstBaseURL: false)
    else {
      return realtimeBaseURL
    }

    components.queryItems = components.queryItems ?? []
    components.queryItems!.append(URLQueryItem(name: "apikey", value: config.apiKey))
    components.queryItems!.append(URLQueryItem(name: "vsn", value: "1.0.0"))

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    guard let url = components.url else {
      return realtimeBaseURL
    }

    return url
  }

  private var broadcastURL: URL {
    config.url.appendingPathComponent("api/broadcast")
  }
}

struct TimeoutError: Error {}

func withThrowingTimeout<R: Sendable>(
  seconds: TimeInterval,
  body: @escaping @Sendable () async throws -> R
) async throws -> R {
  try await withThrowingTaskGroup(of: R.self) { group in
    group.addTask {
      try await body()
    }

    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds) * NSEC_PER_SEC)
      throw TimeoutError()
    }

    let result = try await group.next()!
    group.cancelAll()
    return result
  }
}

extension Task where Success: Sendable, Failure == any Error {
  init(
    priority: TaskPriority? = nil,
    timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> Success
  ) {
    self = Task(priority: priority) {
      try await withThrowingTimeout(seconds: timeout, body: operation)
    }
  }
}
