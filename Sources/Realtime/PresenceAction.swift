//
//  PresenceAction.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation
import Helpers

public struct PresenceV2: Hashable, Sendable {
  /// The presence reference of the object.
  public let ref: String

  /// The object the other client is tracking. Can be done via the
  /// ``RealtimeChannelV2/track(state:)`` method.
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

    let codingPath = container.codingPath + [
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

  /// Decode ``state``.
  ///
  /// - Note: You can also receive your own presence, but without your state so be aware of
  /// exceptions.
  public func decodeState<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = AnyJSON.decoder
  ) throws -> T {
    try state.decode(as: T.self, decoder: decoder)
  }
}

/// Represents a presence action.
public protocol PresenceAction: Sendable, HasRawMessage {
  /// Represents a map of ``PresenceV2`` objects indexed by their key.
  ///
  /// Your own key can be customized when creating the channel within the presence config.
  var joins: [String: PresenceV2] { get }

  /// Represents a map of ``PresenceV2`` objects indexed by their key.
  ///
  /// Your own key can be customized when creating the channel within the presence config.
  var leaves: [String: PresenceV2] { get }
}

extension PresenceAction {
  /// Decode all ``PresenceAction/joins`` values.
  /// - Parameters:
  ///   - ignoreOtherTypes: Whether to ignore presences which cannot be decoded such as your own
  /// presence.
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

  /// Decode all ``PresenceAction/leaves`` values.
  /// - Parameters:
  ///   - ignoreOtherTypes: Whether to ignore presences which cannot be decoded such as your own
  /// presence.
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
  var rawMessage: RealtimeMessage
}
