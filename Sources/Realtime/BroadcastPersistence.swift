//
//  BroadcastPersistence.swift
//  Realtime
//

import Foundation
import Helpers

/// Asks the server to store a broadcast message, so that a channel that joins later with
/// broadcast replay receives it.
///
/// Pass it as the `persist` argument of ``RealtimeChannel/broadcast(event:payload:persist:encoder:)``
/// or ``RealtimeChannel/httpSend(event:payload:persist:timeout:encoder:)``:
///
/// ```swift
/// let channel = await realtime.channel("room") { config in
///   config.isPrivate = true
///   config.broadcast.acknowledgesMessages = true
/// }
/// try await channel.subscribe()
/// try await channel.broadcast(
///   event: "message", payload: message, persist: BroadcastPersistence(ttl: .seconds(3600)))
/// ```
///
/// Storing needs a private channel (``RealtimeChannelConfiguration/isPrivate``) and a
/// `persistence` policy on `realtime.messages` for the sender. On a public channel the send
/// throws ``RealtimeError/Kind-swift.struct/invalidRequest`` and sends nothing.
///
/// Over the WebSocket, only a channel with
/// ``RealtimeChannelConfiguration/Broadcast-swift.struct/acknowledgesMessages`` learns whether
/// the server stored the message. Without it, the server does not reply, and the send returns
/// even when the message was not stored.
public struct BroadcastPersistence: Hashable, Sendable {
  /// How long the server keeps the message. `nil` keeps it for the server's maximum retention.
  ///
  /// The server counts whole seconds, so the SDK sends the whole seconds of the value and drops
  /// any fraction. The SDK does not check the range: the server owns the maximum retention, and
  /// it refuses a value it does not allow with
  /// ``RealtimeError/Code-swift.struct/persistenceInvalidTTL``.
  public var ttl: Duration?

  /// Creates a request to store a broadcast message.
  ///
  /// - Parameter ttl: How long the server keeps the message. `nil` keeps it for the server's
  ///   maximum retention.
  public init(ttl: Duration? = nil) {
    self.ttl = ttl
  }

  /// The whole seconds of ``ttl``, as the server reads them.
  private var ttlSeconds: Int64? {
    ttl?.components.seconds
  }

  /// The frame metadata of a WebSocket broadcast: `{"persist": true}` or
  /// `{"persist": {"ttl": 3600}}`.
  var frameMetadata: JSONObject {
    guard let ttlSeconds else { return ["persist": true] }
    return ["persist": ["ttl": .number(JSONNumber(ttlSeconds))]]
  }

  /// The query item of a REST broadcast: `persist=true` or `persist[ttl]=3600`.
  var queryItem: URLQueryItem {
    guard let ttlSeconds else { return URLQueryItem(name: "persist", value: "true") }
    return URLQueryItem(name: "persist[ttl]", value: String(ttlSeconds))
  }
}
