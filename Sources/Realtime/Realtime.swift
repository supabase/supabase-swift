//
//  Realtime.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Combine
import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

public protocol AuthTokenProvider {
  func authToken() async -> String?
}

public final class Realtime {
  public struct Configuration {
    var url: URL
    var apiKey: String
    var authTokenProvider: AuthTokenProvider?
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var jwtToken: String?
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool

    public init(
      url: URL,
      apiKey: String,
      authTokenProvider: AuthTokenProvider?,
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      jwtToken: String? = nil,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true
    ) {
      self.url = url
      self.apiKey = apiKey
      self.authTokenProvider = authTokenProvider
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.jwtToken = jwtToken
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
    }
  }

  public enum Status {
    case disconnected
    case connecting
    case connected
  }

  let config: Configuration

  var ws: WebSocketClientProtocol?
  let makeWebSocketClient: (URL) -> WebSocketClientProtocol

  let _status = CurrentValueSubject<Status, Never>(.disconnected)
  public var status: Status {
    _status.value
  }

  let _subscriptions = LockIsolated<[String: RealtimeChannel]>([:])
  public var subscriptions: [String: RealtimeChannel] {
    _subscriptions.value
  }

  var heartbeatTask: Task<Void, Never>?
  var messageTask: Task<Void, Never>?

  private var ref = 0
  var heartbeatRef = 0

  init(config: Configuration, makeWebSocketClient: @escaping (URL) -> WebSocketClientProtocol) {
    self.config = config
    self.makeWebSocketClient = makeWebSocketClient
  }

  deinit {
    heartbeatTask?.cancel()
    messageTask?.cancel()
    Task {
      await ws?.cancel()
    }
  }

  public convenience init(config: Configuration) {
    self.init(
      config: config,
      makeWebSocketClient: { WebSocketClient(realtimeURL: $0, configuration: .default) }
    )
  }

  public func connect() async throws {
    try await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async throws {
    if reconnect {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

      if Task.isCancelled {
        debug("reconnect cancelled, returning")
        return
      }
    }

    if status == .connected {
      debug("Websocket already connected")
      return
    }

    _status.value = .connecting

    let realtimeURL = realtimeWebSocketURL

    ws = makeWebSocketClient(realtimeURL)

    let connectionStatus = try await ws?.connect().first { _ in true }

    if connectionStatus == .open {
      _status.value = .connected
      debug("Connected to realtime websocket")
      listenForMessages()
      startHeartbeating()
      if reconnect {
        try await rejoinChannels()
      }
    } else {
      debug(
        "Error while trying to connect to realtime websocket. Trying again in \(config.reconnectDelay) seconds."
      )
      await disconnect()
      try await connect(reconnect: true)
    }
  }

  public func channel(
    _ topic: String,
    options: (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "")
    )
    options(&config)

    return RealtimeChannel(
      topic: "realtime:\(topic)",
      socket: self,
      broadcastJoinConfig: config.broadcast,
      presenceJoinConfig: config.presence
    )
  }

  public func addChannel(_ channel: RealtimeChannel) {
    _subscriptions.withValue { $0[channel.topic] = channel }
  }

  public func removeChannel(_ channel: RealtimeChannel) async throws {
    if channel.status == .subscribed {
      try await channel.unsubscribe()
    }

    _subscriptions.withValue {
      $0[channel.topic] = nil
    }
  }

  private func rejoinChannels() async throws {
    // TODO: should we fire all subscribe calls concurrently?
    for channel in subscriptions.values {
      try await channel.subscribe()
    }
  }

  private func listenForMessages() {
    Task { [weak self] in
      guard let self, let ws else { return }

      do {
        for try await message in await ws.receive() {
          try await onMessage(message)
        }
      } catch {
        debug(
          "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
        )
        await disconnect()
        try await connect(reconnect: true)
      }
    }
  }

  private func startHeartbeating() {
    Task { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.heartbeatInterval))
        if Task.isCancelled {
          break
        }
        try? await sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async throws {
    if heartbeatRef != 0 {
      heartbeatRef = 0
      ref = 0
      debug("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      await disconnect()
      try await connect(reconnect: true)
      return
    }

    heartbeatRef = makeRef()

    try await ws?.send(_RealtimeMessage(
      joinRef: nil,
      ref: heartbeatRef.description,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    ))
  }

  public func disconnect() async {
    debug("Closing websocket connection")
    messageTask?.cancel()
    await ws?.cancel()
    ws = nil
    heartbeatTask?.cancel()
    _status.value = .disconnected
  }

  func makeRef() -> Int {
    ref += 1
    return ref
  }

  private func onMessage(_ message: _RealtimeMessage) async throws {
    let channel = subscriptions[message.topic]
    if Int(message.ref ?? "") == heartbeatRef {
      debug("heartbeat received")
      heartbeatRef = 0
    } else {
      debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      try await channel?.onMessage(message)
    }
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

  var broadcastURL: URL {
    config.url.appendingPathComponent("api/broadcast")
  }
}

protocol WebSocketClientProtocol {
  func send(_ message: _RealtimeMessage) async throws
  func receive() async -> AsyncThrowingStream<_RealtimeMessage, Error>
  func connect() async -> AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>
  func cancel() async
}

actor WebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClientProtocol {
  private var session: URLSession?
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration

  private var task: URLSessionWebSocketTask?

  enum ConnectionStatus {
    case open
    case close
  }

  private var statusContinuation: AsyncThrowingStream<ConnectionStatus, Error>.Continuation?

  init(realtimeURL: URL, configuration: URLSessionConfiguration) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    super.init()
  }

  deinit {
    statusContinuation?.finish()
    task?.cancel()
  }

  func connect() -> AsyncThrowingStream<ConnectionStatus, Error> {
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    task = session?.webSocketTask(with: realtimeURL)

    let (stream, continuation) = AsyncThrowingStream<ConnectionStatus, Error>.makeStream()
    statusContinuation = continuation

    task?.resume()

    return stream
  }

  func cancel() {
    task?.cancel()
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    Task {
      await statusContinuation?.yield(.open)
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    Task {
      await statusContinuation?.yield(.close)
    }
  }

  nonisolated func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    Task {
      await statusContinuation?.finish(throwing: error)
    }
  }

  func receive() -> AsyncThrowingStream<_RealtimeMessage, Error> {
    let (stream, continuation) = AsyncThrowingStream<_RealtimeMessage, Error>.makeStream()

    Task {
      while let message = try await self.task?.receive() {
        do {
          switch message {
          case let .string(stringMessage):
            guard let data = stringMessage.data(using: .utf8) else {
              throw RealtimeError("Expected a UTF8 encoded message.")
            }

            let message = try JSONDecoder().decode(_RealtimeMessage.self, from: data)
            continuation.yield(message)

          case .data:
            fallthrough
          default:
            throw RealtimeError("Unsupported message type.")
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    return stream
  }

  func send(_ message: _RealtimeMessage) async throws {
    let data = try JSONEncoder().encode(message)
    let string = String(decoding: data, as: UTF8.self)
    try await task?.send(.string(string))
  }
}
