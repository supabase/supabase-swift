//
//  Realtime+Push.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation
import Helpers

// MARK: - Channel seam (internal API consumed by Channel)

extension Realtime {
  /// Returns the next monotonic ref string from the shared generator.
  nonisolated func nextRef() -> String {
    refGenerator.next()
  }

  /// Sends a raw frame on the current connection without lazy-connecting.
  ///
  /// Throws `.disconnected` if no connection is available, `.transportFailure` if the send
  /// fails. This is the single point where any frame reaches the socket.
  func _rawSend(_ frame: TransportFrame) async throws(RealtimeError) {
    guard let conn = connection else {
      throw .disconnected
    }
    do {
      try await conn.send(frame)
    } catch {
      throw .transportFailure(underlying: error)
    }
  }

  /// Encodes and sends a single Phoenix frame, optionally awaiting its `phx_reply`.
  ///
  /// The single funnel for every framed send — channel pushes (broadcast, presence, join,
  /// leave, access_token) and the connection heartbeat all route through here. Handles ref
  /// generation, text/binary encoding (mapping encode failures to `.encoding`), the send,
  /// and — when `ack == .require` — reply correlation via the in-flight registry. Send
  /// failures (`.transportFailure`/`.disconnected`) propagate unchanged.
  ///
  /// Because the registry buffers early replies, awaiting *after* sending is race-free, so
  /// every ack site uses this one flow (no manual pre-register task needed).
  ///
  /// - Parameters:
  ///   - topic: The Phoenix topic (e.g. a channel's `realtime:` topic, or `"phoenix"` for heartbeat).
  ///   - event: The Phoenix event for the frame.
  ///   - body: The wire payload (text JSON, or a binary broadcast frame).
  ///   - ref: The push ref. Defaults to a fresh `nextRef()`; `join` passes its own ref so
  ///     `ref == joinRef`.
  ///   - joinRef: The join ref stamped on the frame.
  ///   - lazyConnect: When `true` (default) the socket is opened if needed before sending
  ///     (spec §6.1). The heartbeat passes `false` — it must report a dead connection via the
  ///     ack timeout rather than trigger a reconnect.
  ///   - ack: Whether to await a reply.
  /// - Returns: The `phx_reply` when `ack == .require`, otherwise `nil`.
  @discardableResult
  func _push(
    topic: String,
    _ event: PhoenixEvent,
    _ body: PushBody,
    ref: String? = nil,
    joinRef: String? = nil,
    lazyConnect: Bool = true,
    ack: AckPolicy = .none
  ) async throws(RealtimeError) -> PushReply? {
    let ref = ref ?? nextRef()

    let frame: TransportFrame
    do {
      switch body {
      case .text(let payload):
        frame = .text(
          try serializer.encodeText(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, payload: payload))
      case .broadcastJSON(let payload):
        frame = .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, jsonPayload: payload))
      case .broadcastData(let payload):
        frame = .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, binaryPayload: payload)
        )
      }
    } catch {
      throw .encoding(underlying: error)
    }

    // Lazy connect (idempotent) then send. The heartbeat opts out so a dead socket surfaces
    // as `.disconnected` rather than kicking off a reconnect that races the recovery loop.
    if lazyConnect {
      try await connect()
    }
    let wallClock = ContinuousClock()
    let sentAt = wallClock.now
    try await _rawSend(frame)

    switch ack {
    case .none:
      return nil
    case .require(let timeout, let error):
      let reply = try await awaitReply(ref: ref, timeout: timeout, timeoutError: error)
      // Emit the acked-broadcast round-trip metric (spec §10 metrics-as-logs). The heartbeat
      // reports its own `heartbeat.rtt_ms`; join/leave/presence acks have no defined metric.
      if event == .broadcast {
        log(
          .debug, .broadcast, "Broadcast acknowledged",
          metadata: [
            "broadcast.ack_latency_ms": "\(sentAt.duration(to: wallClock.now).inMilliseconds)"
          ]
        )
      }
      return reply
    }
  }

  /// Encodes an `Encodable` value to `AnyJSON` using `configuration.encoder`, mapping any
  /// failure to `.encoding`. Shared by channel broadcast/presence payloads and HTTP broadcast.
  ///
  /// `nonisolated`: it only reads the immutable, Sendable `configuration` and does pure
  /// encoding, so callers (including the synchronous `Channel._encodeToJSON`) need no `await`.
  nonisolated func _encodeToJSON<T: Encodable & Sendable>(_ value: T) throws(RealtimeError)
    -> AnyJSON
  {
    do {
      let data = try configuration.encoder.encode(value)
      return try JSONDecoder().decode(AnyJSON.self, from: data)
    } catch {
      throw .encoding(underlying: error)
    }
  }

  /// Registers `ref` with the in-flight registry and suspends until the matching
  /// `phx_reply` arrives or `timeout` elapses on `configuration.clock`.
  func awaitReply(
    ref: String,
    timeout: Duration,
    timeoutError: RealtimeError
  ) async throws(RealtimeError) -> PushReply {
    try await inflightPushRegistry.awaitReply(
      ref: ref,
      timeout: timeout,
      clock: configuration.clock,
      timeoutError: timeoutError
    )
  }

  /// Returns the current access token for channel join, consulting stored state in order:
  ///
  /// 1. `_overrideToken` — set by `updateToken(_:)`; takes highest precedence.
  /// 2. `accessTokenProvider` — async closure supplied at init.
  /// 3. `nil` — anonymous / public channels (no token configured).
  ///
  /// This ordering ensures a token pushed via `updateToken(_:)` is immediately
  /// used for any subsequent joins, regardless of whether a provider is also set.
  func accessTokenForJoin() async throws(RealtimeError) -> String? {
    if let override = _overrideToken { return override }
    guard let provider = accessTokenProvider else { return nil }
    do {
      return try await provider()
    } catch {
      throw .authenticationFailed(
        reason: "Access token provider threw an error.", underlying: error)
    }
  }
}
