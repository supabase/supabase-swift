//
//  Presence.swift
//  Realtime
//
//  Created by Guilherme Souza on 29/10/26.
//

public import Foundation

/// One tracked client under a presence key.
///
/// A presence key groups every client that tracks under it, so one key holds one entry per
/// device or tab. Set the key with ``RealtimeChannelConfiguration/Presence-swift.struct/key``;
/// when it is `nil`, the server gives each client its own random key.
///
/// ## Topics
/// ### Properties
/// - ``ref``
/// - ``previousRef``
/// - ``payload``
/// ### Decoding
/// - ``decode(as:decoder:)``
public struct PresenceEntry: Sendable, Hashable {
  /// The server-assigned reference that identifies this entry.
  public var ref: String

  /// The reference of the entry this one replaced, when the client called
  /// ``RealtimeChannel/track(_:encoder:)`` again.
  public var previousRef: String?

  /// The payload the client passed to ``RealtimeChannel/track(_:encoder:)``.
  public var payload: JSONObject

  /// Creates a presence entry.
  ///
  /// - Parameters:
  ///   - ref: The server-assigned reference.
  ///   - previousRef: The reference of the entry this one replaced.
  ///   - payload: The tracked payload.
  public init(ref: String, previousRef: String? = nil, payload: JSONObject) {
    self.ref = ref
    self.previousRef = previousRef
    self.payload = payload
  }

  /// Decodes ``payload`` into a `Decodable` model.
  ///
  /// - Parameters:
  ///   - type: The target type. Can be inferred from context.
  ///   - decoder: The decoder to use. Defaults to ``JSONValue/decoder``.
  /// - Returns: The decoded payload.
  /// - Throws: A `DecodingError` when the payload does not match `T`.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = JSONValue.decoder
  ) throws -> T {
    try payload.decode(as: T.self, decoder: decoder)
  }
}

/// The clients present on a channel, by presence key.
///
/// Read it with ``RealtimeChannel/presenceState`` or observe it with
/// ``RealtimeChannel/presenceStates()``.
///
/// ## Topics
/// ### Properties
/// - ``entries``
/// ### Decoding
/// - ``decode(as:decoder:ignoringUndecodable:)``
public struct PresenceState: Sendable, Hashable {
  /// The entries of each presence key. A key with several entries is a client on several
  /// devices or tabs.
  public var entries: [String: [PresenceEntry]]

  /// Creates a presence state.
  ///
  /// - Parameter entries: The entries of each presence key.
  public init(entries: [String: [PresenceEntry]] = [:]) {
    self.entries = entries
  }

  /// Decodes the payload of every entry into a `Decodable` model.
  ///
  /// - Parameters:
  ///   - type: The target type. Can be inferred from context.
  ///   - decoder: The decoder to use. Defaults to ``JSONValue/decoder``.
  ///   - ignoringUndecodable: When `true`, entries that do not decode as `T` are skipped, and
  ///     keys with no decoded entry are left out. Clients that track other payloads, or none,
  ///     do not make the call fail. Defaults to `true`.
  /// - Returns: The decoded payloads of each presence key.
  /// - Throws: A `DecodingError` when `ignoringUndecodable` is `false` and an entry does not
  ///   decode as `T`.
  public func decode<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = JSONValue.decoder,
    ignoringUndecodable: Bool = true
  ) throws -> [String: [T]] {
    var decoded: [String: [T]] = [:]
    for (key, entries) in entries {
      let values: [T] =
        if ignoringUndecodable {
          entries.compactMap { try? $0.decode(as: T.self, decoder: decoder) }
        } else {
          try entries.map { try $0.decode(as: T.self, decoder: decoder) }
        }
      if !values.isEmpty { decoded[key] = values }
    }
    return decoded
  }
}

/// The entries that joined and left a channel's presence in one sync.
///
/// Received from ``RealtimeChannel/presenceChanges()``. An update to a tracked payload shows up
/// as a join of the new entry, with ``PresenceEntry/previousRef`` set, and a leave of the old one.
///
/// ## Topics
/// ### Properties
/// - ``joins``
/// - ``leaves``
public struct PresenceChange: Sendable, Hashable {
  /// The entries that joined, by presence key.
  public var joins: [String: [PresenceEntry]]

  /// The entries that left, by presence key.
  public var leaves: [String: [PresenceEntry]]

  /// Creates a presence change.
  ///
  /// - Parameters:
  ///   - joins: The entries that joined, by presence key.
  ///   - leaves: The entries that left, by presence key.
  public init(
    joins: [String: [PresenceEntry]] = [:], leaves: [String: [PresenceEntry]] = [:]
  ) {
    self.joins = joins
    self.leaves = leaves
  }

  var isEmpty: Bool {
    joins.isEmpty && leaves.isEmpty
  }
}
