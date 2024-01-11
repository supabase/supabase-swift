//
//  PresenceAction.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation
@_spi(Internal) import _Helpers

public struct _Presence: Hashable, Sendable {
  public let ref: String
  public let state: JSONObject
}

extension _Presence: Codable {
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

  public init(from decoder: Decoder) throws {
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
          debugDescription: "A presence should at least have a phx_ref"
        )
      )
    }

    guard let presenceRef = meta["phx_ref"]?.stringValue else {
      throw DecodingError.typeMismatch(
        String.self,
        DecodingError.Context(
          codingPath: codingPath + [_StringCodingKey("phx_ref")],
          debugDescription: "A presence should at least have a phx_ref"
        )
      )
    }

    meta["phx_ref"] = nil
    self = _Presence(ref: presenceRef, state: meta)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: _StringCodingKey.self)
    try container.encode(ref, forKey: _StringCodingKey("phx_ref"))
    try container.encode(state, forKey: _StringCodingKey("state"))
  }
}

public protocol PresenceAction: Sendable, HasRawMessage {
  var joins: [String: _Presence] { get }
  var leaves: [String: _Presence] { get }
}

extension PresenceAction {
  public func decodeJoins<T: Decodable>(as _: T.Type, ignoreOtherTypes: Bool = true) throws -> [T] {
    if ignoreOtherTypes {
      return joins.values.compactMap { try? $0.state.decode(T.self) }
    }

    return try joins.values.map { try $0.state.decode(T.self) }
  }

  public func decodeLeaves<T: Decodable>(
    as _: T.Type,
    ignoreOtherTypes: Bool = true
  ) throws -> [T] {
    if ignoreOtherTypes {
      return leaves.values.compactMap { try? $0.state.decode(T.self) }
    }

    return try leaves.values.map { try $0.state.decode(T.self) }
  }
}

struct PresenceActionImpl: PresenceAction {
  var joins: [String: _Presence]
  var leaves: [String: _Presence]
  var rawMessage: RealtimeMessageV2
}
