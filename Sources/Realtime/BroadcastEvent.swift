//
//  BroadcastEvent.swift
//  Realtime
//

import ConcurrencyExtras
public import Foundation
import IssueReporting

/// A type that is the payload of one broadcast event.
///
/// The type names its event, so one declaration sets the event name for both sending and
/// receiving. A typo in the name cannot make the two sides disagree.
///
/// ```swift
/// struct Cursor: BroadcastEvent, Codable {
///   static let event = "cursor"
///   var x: Double
///   var y: Double
/// }
///
/// let cursors = await channel.broadcasts(of: Cursor.self)
/// try await channel.subscribe()
/// try await channel.broadcast(Cursor(x: 10, y: 20))
///
/// for await message in cursors {
///   let cursor = try message.payload()
/// }
/// ```
///
/// Set ``event`` to a fixed string. Clients in other languages use the same name, so do not
/// derive it from the type name. Do not use `"*"`: a stream that listens for `"*"` receives
/// every broadcast on the channel, so ``TypedBroadcastMessage/payload()`` throws for most of them.
/// The SDK reports an issue when a typed stream or a typed send uses `"*"`.
public protocol BroadcastEvent {
  /// The broadcast event name on the wire.
  static var event: String { get }
}

extension BroadcastEvent {
  /// ``event``, after it reports an issue if the name is `"*"`. The name is still used, so the
  /// call behaves as its string-keyed form would.
  static var checkedEvent: String {
    let event = Self.event
    if event == "*" {
      reportIssue(
        """
        \(Self.self).event is "*", which matches every broadcast on the channel. Give the type \
        its own event name, or use the string-keyed broadcast API to listen to every event.
        """
      )
    }
    return event
  }
}

/// A ``BroadcastMessage`` bound to an event type, usually a ``BroadcastEvent``. Call
/// ``payload()`` to decode it.
///
/// The SDK does not decode the payload before it delivers the message, so a payload that does
/// not decode never drops the message or ends the stream: ``payload()`` throws at the call site
/// instead.
///
/// `Event` is a phantom type with no constraint: no `Event` value is stored, so the message is
/// `Sendable` for any `Event`. Only ``payload()`` needs `Event: Decodable`, so an event type
/// whose conformances are isolated to the main actor works from the main actor.
public struct TypedBroadcastMessage<Event>: Sendable {
  /// The message as the server sent it.
  public var raw: BroadcastMessage
  // `JSONDecoder` is `Sendable` only from iOS 17 and macOS 14. Nothing mutates it after the call
  // that made this message.
  let decoder: UncheckedSendable<JSONDecoder>
}

extension TypedBroadcastMessage where Event: Decodable {
  /// Decodes the payload as `Event`. A ``BroadcastPayload/binary(_:)`` payload is read as JSON.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/decoding`` when the
  ///   payload does not decode as `Event`. The underlying `DecodingError` is in
  ///   ``RealtimeError/underlyingError``.
  public func payload() throws -> Event {
    try raw.decode(as: Event.self, decoder: decoder.value)
  }
}
