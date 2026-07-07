//
//  PresenceAction.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

public import Foundation

/// The presence state of a single client tracked on a Realtime channel.
///
/// Instances are received via ``PresenceAction/joins`` and ``PresenceAction/leaves``
/// when other clients call ``RealtimeChannelV2/track(_:)`` or ``RealtimeChannelV2/untrack()``.
///
/// ## Topics
/// ### Properties
/// - ``ref``
/// - ``state``
/// ### Decoding
/// - ``decodeState(as:decoder:)``
public struct PresenceV2: Hashable, Sendable {
  /// The server-assigned presence reference string that uniquely identifies this presence entry.
  public let ref: String

  /// The arbitrary state payload the client published via ``RealtimeChannelV2/track(_:)``,
  /// stored as a ``JSONObject``.
  public let state: JSONObject
}

extension PresenceV2: Codable {
  struct _StringCodingKey: CodingKey {
    var stringValue: String

    init(_ stringValue: String) {
      self.init(stringValue: stringValue)!
    }

    init?(stringValue: String) {
      self.stringValue = stringValue
    }

    var intValue: Int?

    init?(intValue: Int) {
      stringValue = "\(intValue)"
      self.intValue = intValue
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    let json = try container.decode(JSONObject.self)

    let codingPath =
      container.codingPath + [
        _StringCodingKey("metas"),
        _StringCodingKey(intValue: 0)!,
      ]

    guard var meta = json["metas"]?.arrayValue?.first?.objectValue else {
      throw DecodingError.typeMismatch(
        JSONObject.self,
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "A presence should at least have a phx_ref."
        )
      )
    }

    guard let presenceRef = meta["phx_ref"]?.stringValue else {
      throw DecodingError.typeMismatch(
        String.self,
        DecodingError.Context(
          codingPath: codingPath + [_StringCodingKey("phx_ref")],
          debugDescription: "A presence should at least have a phx_ref."
        )
      )
    }

    meta["phx_ref"] = nil
    self = PresenceV2(ref: presenceRef, state: meta)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: _StringCodingKey.self)
    try container.encode(ref, forKey: _StringCodingKey("phx_ref"))
    try container.encode(state, forKey: _StringCodingKey("state"))
  }

  /// Decodes the ``state`` dictionary into a `Decodable` model.
  ///
  /// > Note: You may receive your own presence entry, but without your state payload,
  /// > so be prepared to handle decoding failures gracefully.
  ///
  /// - Parameters:
  ///   - type: The target `Decodable` type. Can be inferred from context.
  ///   - decoder: A `JSONDecoder` to use. Defaults to `AnyJSON.decoder`.
  /// - Returns: An instance of `T` decoded from the state data.
  /// - Throws: A `DecodingError` if the state cannot be decoded into `T`.
  public func decodeState<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    try state.decode(as: T.self, decoder: decoder)
  }
}

/// An event describing clients joining and leaving a Realtime channel's presence set.
///
/// Received via ``RealtimeChannelV2/onPresenceChange(_:)`` or
/// ``RealtimeChannelV2/presenceChange()``.
///
/// ## Topics
/// ### Presence Maps
/// - ``joins``
/// - ``leaves``
/// ### Decoding Helpers
/// - ``decodeJoins(as:ignoreOtherTypes:decoder:)``
/// - ``decodeLeaves(as:ignoreOtherTypes:decoder:)``
public protocol PresenceAction: Sendable, HasRawMessage {
  /// A map of presence entries that joined the channel since the last event, keyed by the
  /// client-defined presence key (configured via ``PresenceJoinConfig/key``).
  var joins: [String: PresenceV2] { get }

  /// A map of presence entries that left the channel since the last event, keyed by the
  /// client-defined presence key.
  var leaves: [String: PresenceV2] { get }
}

extension PresenceAction {
  /// Decodes all ``joins`` entries into an array of `Decodable` values.
  ///
  /// - Parameters:
  ///   - type: The target `Decodable` type. Can be inferred from context.
  ///   - ignoreOtherTypes: When `true`, presences whose state cannot be decoded to `T` are
  ///     silently skipped (e.g. your own presence without a state payload). Defaults to `true`.
  ///   - decoder: A `JSONDecoder` to use. Defaults to `AnyJSON.decoder`.
  /// - Returns: An array of `T` values decoded from the joined presences.
  /// - Throws: A `DecodingError` when `ignoreOtherTypes` is `false` and any presence cannot be decoded.
  public func decodeJoins<T: Decodable>(
    as _: T.Type = T.self,
    ignoreOtherTypes: Bool = true,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> [T] {
    if ignoreOtherTypes {
      return joins.values.compactMap { try? $0.decodeState(as: T.self, decoder: decoder) }
    }

    return try joins.values.map { try $0.decodeState(as: T.self, decoder: decoder) }
  }

  /// Decodes all ``leaves`` entries into an array of `Decodable` values.
  ///
  /// - Parameters:
  ///   - type: The target `Decodable` type. Can be inferred from context.
  ///   - ignoreOtherTypes: When `true`, presences whose state cannot be decoded to `T` are
  ///     silently skipped. Defaults to `true`.
  ///   - decoder: A `JSONDecoder` to use. Defaults to `AnyJSON.decoder`.
  /// - Returns: An array of `T` values decoded from the leaving presences.
  /// - Throws: A `DecodingError` when `ignoreOtherTypes` is `false` and any presence cannot be decoded.
  public func decodeLeaves<T: Decodable>(
    as _: T.Type = T.self,
    ignoreOtherTypes: Bool = true,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> [T] {
    if ignoreOtherTypes {
      return leaves.values.compactMap { try? $0.decodeState(as: T.self, decoder: decoder) }
    }

    return try leaves.values.map { try $0.decodeState(as: T.self, decoder: decoder) }
  }
}

struct PresenceActionImpl: PresenceAction {
  var joins: [String: PresenceV2]
  var leaves: [String: PresenceV2]
  var rawMessage: RealtimeMessageV2
}
