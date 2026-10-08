//
//  RealtimePresence.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

public import Foundation

/// Presence on one channel: who is there, and this client's own entry.
///
/// Making a ``states`` or ``changes`` stream, or calling ``track(_:encoder:)``, makes the channel
/// join with presence enabled. The server sends the presence set only to such a join, so the
/// first stream on a channel that is already joined without presence makes it join again.
public struct RealtimePresence: Sendable {
  private let channel: RealtimeChannel

  init(channel: RealtimeChannel) {
    self.channel = channel
  }

  /// The presence set, read without waiting. It is empty until the server sends the set for the
  /// current join.
  public var state: PresenceState {
    channel.engine.mirror.presence(channel.wireTopic, owner: channel.owner.id)
  }

  /// The whole presence set after every update from the server.
  public var states: RealtimeStream<PresenceState> {
    channel.enablePresence()
    return RealtimeStream(channel.engine.inbound(channel.wireTopic, owner: channel.owner)) {
      inbound in
      guard case .presenceChanged(_, let state) = inbound else { return nil }
      return state
    }
  }

  /// The entries that joined and left in every update from the server.
  public var changes: RealtimeStream<PresenceChange> {
    channel.enablePresence()
    return RealtimeStream(channel.engine.inbound(channel.wireTopic, owner: channel.owner)) {
      inbound in
      guard case .presenceChanged(let change, _) = inbound else { return nil }
      return change
    }
  }

  /// Publishes `payload` as this client's presence entry.
  ///
  /// The SDK sends the payload again after every rejoin until ``untrack()``. The server accepts
  /// a few presence calls per window, so the SDK sends at most one call every few seconds. A call
  /// inside that window returns once the payload is queued, without waiting for the server; the
  /// newest queued payload goes out when the window ends. A payload equal to the last one sent
  /// is not sent again.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/encoding`` when `payload` does not
  ///   encode, ``RealtimeError/Kind/notSubscribed`` when the channel is not joined,
  ///   ``RealtimeError/Kind/notConnected`` when the socket is down or goes away before the
  ///   reply, ``RealtimeError/Kind/timeout`` when the server does not reply, and the server's
  ///   error when it refuses the call.
  public func track(_ payload: some Encodable, encoder: JSONEncoder = .supabase()) async throws {
    let value: JSONValue
    do {
      value = try JSONValue(payload, encoder: encoder)
    } catch {
      throw RealtimeError(
        kind: .encoding, message: "presence payload did not encode", underlyingError: error)
    }
    guard let object = value.objectValue else {
      throw RealtimeError(kind: .encoding, message: "presence payload must be a JSON object")
    }
    try await channel.engine.trackPresence(channel.wireTopic, owner: channel.owner, payload: object)
  }

  /// Removes this client's presence entry, and stops sending it after a rejoin.
  ///
  /// The same rate window as ``track(_:encoder:)`` applies, with the same early return.
  ///
  /// - Throws: The same errors as ``track(_:encoder:)``, except the encoding error.
  public func untrack() async throws {
    try await channel.engine.untrackPresence(channel.wireTopic, owner: channel.owner)
  }
}
