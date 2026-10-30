import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers

@testable import Realtime

final class FakeWebSocket: WebSocketConnection {
  struct MutableState {
    var isClosed: Bool = false
    weak var other: FakeWebSocket?

    var sentEvents: [WebSocketEvent] = []
    var receivedEvents: [WebSocketEvent] = []
    var closeCode: Int?
    var closeReason: String?
    var onSend: (@Sendable (WebSocketFrame) async -> Void)?
  }

  private let mutableState = LockIsolated(MutableState())
  let events: AsyncStream<WebSocketEvent>
  private let eventsContinuation: AsyncStream<WebSocketEvent>.Continuation

  private init() {
    (events, eventsContinuation) = AsyncStream.makeStream()
  }

  var sentEvents: [WebSocketEvent] {
    mutableState.value.sentEvents
  }

  /// The binary frames sent so far, waiting up to `timeout` for the first one: the client's
  /// writer sends a frame after the call that queued it returns.
  func sentBinaryFrames(timeout: Duration = .seconds(5)) async -> [Data] {
    await waitUntil(timeout: timeout.timeInterval) { !self.binaryFrames.isEmpty }
    return binaryFrames
  }

  private var binaryFrames: [Data] {
    sentEvents.compactMap { event in
      if case .frame(.binary(let data)) = event { data } else { nil }
    }
  }

  var receivedEvents: [WebSocketEvent] {
    mutableState.value.receivedEvents
  }

  var closeCode: Int? {
    mutableState.value.closeCode
  }

  var closeReason: String? {
    mutableState.value.closeReason
  }

  func close(code: Int?, reason: String?) {
    mutableState.withValue { s in
      if s.isClosed { return }

      let event = WebSocketEvent.closed(
        code: code.map(WebSocketCloseCode.init(rawValue:)), reason: reason)
      s.sentEvents.append(event)

      s.isClosed = true
      s.closeCode = code
      s.closeReason = reason
      if s.other?.isClosed == false {
        s.other?._trigger(event)
      }
    }
  }

  func close(code: WebSocketCloseCode, reason: String?) {
    close(code: code.rawValue, reason: reason)
  }

  func send(_ text: String) {
    send(frame: .text(text))
  }

  func send(_ binary: Data) {
    send(frame: .binary(binary))
  }

  func send(_ frame: WebSocketFrame) async throws {
    send(frame: frame)
    await mutableState.value.onSend?(frame)
  }

  /// Runs `hook` after each frame reaches the peer, before `send` returns. A hook that suspends
  /// keeps the send in flight, as a slow network would.
  func onSend(_ hook: @escaping @Sendable (WebSocketFrame) async -> Void) {
    mutableState.withValue { $0.onSend = hook }
  }

  private func send(frame: WebSocketFrame) {
    mutableState.withValue {
      guard !$0.isClosed else { return }

      $0.sentEvents.append(.frame(frame))

      if $0.other?.isClosed == false {
        $0.other?._trigger(.frame(frame))
      }
    }
  }

  var isClosed: Bool {
    mutableState.value.isClosed
  }

  func _trigger(_ event: WebSocketEvent) {
    mutableState.withValue {
      $0.receivedEvents.append(event)

      if case .closed(let code, let reason) = event {
        $0.isClosed = true
        $0.closeCode = code?.rawValue
        $0.closeReason = reason
      }
    }
    eventsContinuation.yield(event)
    if case .closed = event {
      eventsContinuation.finish()
    }
  }

  static func fakes() -> (FakeWebSocket, FakeWebSocket) {
    let (peer1, peer2) = (FakeWebSocket(), FakeWebSocket())

    peer1.mutableState.withValue { $0.other = peer2 }
    peer2.mutableState.withValue { $0.other = peer1 }

    return (peer1, peer2)
  }
}

/// A transport that hands the client whatever connection `open` returns.
struct ClosureWebSocketTransport: WebSocketTransport {
  let open: @Sendable (URL, HTTPFields) async throws -> any WebSocketConnection

  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    try await open(url, headerFields)
  }
}

extension RealtimeClient {
  /// Builds a client whose transport is the `wsTransport` closure.
  ///
  /// The backoff jitter is pinned to the top of its range, so the n-th reconnect waits exactly
  /// `min(30s, reconnectDelay · 2^(n-1))`.
  init(
    url: URL,
    options: RealtimeClientOptions,
    wsTransport: @escaping @Sendable (URL, HTTPFields) async throws -> any WebSocketConnection,
    http: HTTPClient,
    clock: any Clock<Duration>,
    reconnectBackoff: BackoffPolicy = RealtimeClient.defaultReconnectBackoff,
    jitter: @escaping @Sendable (ClosedRange<Double>) -> Double = { $0.upperBound }
  ) {
    self.init(
      url: url,
      options: options,
      transport: ClosureWebSocketTransport(open: wsTransport),
      http: http,
      clock: clock,
      reconnectBackoff: reconnectBackoff,
      jitter: jitter
    )
  }
}

extension WebSocketEvent {
  /// A close with a plain `Int` code, the way tests script the server.
  static func close(code: Int?, reason: String?) -> WebSocketEvent {
    .closed(code: code.map(WebSocketCloseCode.init(rawValue:)), reason: reason)
  }
}
