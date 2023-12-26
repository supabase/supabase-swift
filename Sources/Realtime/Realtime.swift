//
//  Realtime.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Combine
import ConcurrencyExtras
import Foundation

public final class Realtime {
  public struct Configuration {
    var url: URL
    var apiKey: String
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var jwtToken: String?
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool

    public init(
      url: URL,
      apiKey: String,
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      jwtToken: String? = nil,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true
    ) {
      self.url = url
      self.apiKey = apiKey
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

  let _subscriptions = LockIsolated<[String: _RealtimeChannel]>([:])
  public var subscriptions: [String: _RealtimeChannel] {
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
    ws?.cancel()
  }

  public convenience init(config: Configuration) {
    self.init(
      config: config,
      makeWebSocketClient: { WebSocketClient(realtimeURL: $0, session: .shared) }
    )
  }

  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if reconnect {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

      if Task.isCancelled {
        return
      }
    }

    if status == .connected {
      print("Websocket already connected")
      return
    }

    _status.value = .connecting

    let realtimeURL = realtimeWebSocketURL

    ws = makeWebSocketClient(realtimeURL)

    // TODO: should we consider a timeout?
    // wait for status
    let connectionStatus = await ws?.status.first(where: { _ in true })

    if connectionStatus == .open {
      _status.value = .connected
      print("Connected to realtime websocket")
      listenForMessages()
      startHeartbeating()
      if reconnect {
        await rejoinChannels()
      }
    } else {
      print(
        "Error while trying to connect to realtime websocket. Trying again in \(config.reconnectDelay)"
      )
      disconnect()
      await connect(reconnect: true)
    }
  }

  public func channel(
    _ topic: String,
    options: (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> _RealtimeChannel {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "")
    )
    options(&config)

    return _RealtimeChannel(
      topic: "realtime:\(topic)",
      socket: self,
      broadcastJoinConfig: config.broadcast,
      presenceJoinConfig: config.presence
    )
  }

  public func addChannel(_ channel: _RealtimeChannel) {
    _subscriptions.withValue { $0[channel.topic] = channel }
  }

  public func removeChannel(_ channel: _RealtimeChannel) async throws {
    if channel.status == .subscribed {
      try await channel.unsubscribe()
    }

    _subscriptions.withValue {
      $0[channel.topic] = nil
    }
  }

  private func rejoinChannels() async {
    // TODO: should we fire all subscribe calls concurrently?
    for channel in subscriptions.values {
      await channel.subscribe()
    }
  }

  private func listenForMessages() {
    messageTask = Task { [weak self] in
      guard let self else { return }

      do {
        while let message = try await ws?.receive() {
          await onMessage(message)
        }
      } catch {
        if error is CancellationError {
          return
        }

        print("Error while listening for messages. Trying again in \(config.reconnectDelay)")
        disconnect()
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
        try? await sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async throws {
    if heartbeatRef != 0 {
      heartbeatRef = 0
      ref = 0
      print("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      disconnect()
      await connect(reconnect: true)
      return
    }

    heartbeatRef = makeRef()

    try await ws?.send(_RealtimeMessage(
      topic: "phoenix",
      event: "heartbeat",
      payload: [:],
      ref: heartbeatRef.description
    ))
  }

  public func disconnect() {
    print("Closing websocket connection")
    messageTask?.cancel()
    ws?.cancel()
    ws = nil
    heartbeatTask?.cancel()
    _status.value = .disconnected
  }

  func makeRef() -> Int {
    ref += 1
    return ref
  }

  private func onMessage(_ message: _RealtimeMessage) async {
    let channel = subscriptions[message.topic]
    if Int(message.ref ?? "") == heartbeatRef {
      print("heartbeat received")
      heartbeatRef = 0
    } else {
      print("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      try? await channel?.onMessage(message)
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
  var status: AsyncStream<WebSocketClient.ConnectionStatus> { get }

  func send(_ message: _RealtimeMessage) async throws
  func receive() async throws -> _RealtimeMessage?
  func cancel()
}

final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClientProtocol {
  private var task: URLSessionWebSocketTask?

  enum ConnectionStatus {
    case open
    case close
  }

  let status: AsyncStream<ConnectionStatus>
  private let continuation: AsyncStream<ConnectionStatus>.Continuation

  init(realtimeURL: URL, session: URLSession) {
    (status, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    task = session.webSocketTask(with: realtimeURL)

    super.init()

    task?.resume()
  }

  deinit {
    continuation.finish()
    task?.cancel()
  }

  func cancel() {
    task?.cancel()
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    continuation.yield(.open)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    continuation.yield(.close)
  }

  func receive() async throws -> _RealtimeMessage? {
    switch try await task?.receive() {
    case let .string(stringMessage):
      guard let data = stringMessage.data(using: .utf8),
            let message = try? JSONDecoder().decode(_RealtimeMessage.self, from: data)
      else {
        return nil
      }
      return message
    case .data:
      fallthrough
    default:
      print("Unsupported message type")
      return nil
    }
  }

  func send(_ message: _RealtimeMessage) async throws {
    let data = try JSONEncoder().encode(message)
    let string = String(decoding: data, as: UTF8.self)
    try await task?.send(.string(string))
  }
}
