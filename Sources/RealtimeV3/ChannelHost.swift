//
//  ChannelHost.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation
import Helpers

/// The capabilities a `Channel` needs from its owning client.
///
/// `Channel` depends on this protocol rather than the concrete `Realtime` actor, so the two
/// are decoupled: the channel can be exercised against a test double, and the identity of the
/// host (today `Realtime`, potentially a dedicated connection controller later) is an
/// implementation detail. The surface is exactly what `Channel` consumes — no more.
///
/// `AnyObject`-constrained so `Channel` can hold the host `weak` (cycle-break, see
/// `Channel.realtime`). The synchronous members are `nonisolated` because `Channel` calls them
/// without hopping; the two `async` members run on the host's executor.
protocol ChannelHost: AnyObject, Sendable {
  /// The client configuration (encoder/decoder, timeouts, clock, …).
  nonisolated var configuration: Configuration { get }

  /// Returns the next monotonic ref string from the shared generator.
  nonisolated func nextRef() -> String

  /// Emits a structured log event (no-op if no logger is configured).
  nonisolated func log(
    _ level: LogLevel, _ category: Category, _ message: String, metadata: [String: String])

  /// Records that `topic` has joined (drives the leaked-channel deinit warning + idle timer).
  nonisolated func _markJoined(_ topic: String)

  /// Records that `topic` has been left or terminally evicted.
  nonisolated func _markLeft(_ topic: String)

  /// Encodes an `Encodable` value to `AnyJSON` using the configured encoder.
  nonisolated func _encodeToJSON<T: Encodable & Sendable>(_ value: T) throws(RealtimeError)
    -> AnyJSON

  /// Vends the access token to use for a channel join (`nil` for anonymous channels).
  func accessTokenForJoin() async throws(RealtimeError) -> String?

  /// Encodes and sends a single Phoenix frame for `topic`, optionally awaiting its reply.
  @discardableResult
  func _push(
    topic: String,
    _ event: PhoenixEvent,
    _ body: PushBody,
    ref: String?,
    joinRef: String?,
    lazyConnect: Bool,
    ack: AckPolicy
  ) async throws(RealtimeError) -> PushReply?

  /// Sends one or more broadcast messages over HTTP (no WebSocket required).
  func _httpBroadcastBatch(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError)
}

// `Realtime` already provides every member with matching isolation — the conformance is
// declarative only.
extension Realtime: ChannelHost {}
