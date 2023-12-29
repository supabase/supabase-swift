//
//  PresenceAction.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation

public protocol PresenceAction: HasRawMessage {
  var joins: [String: Presence] { get }
  var leaves: [String: Presence] { get }
}

// extension PresenceAction {
//  public func decodeJoins<T: Decodable>(as _: T.Type, decoder: JSONDecoder, ignoreOtherTypes: Bool
//  = true) throws -> [T] {
//    let result = joins.values.map { $0.state }
//  }
// }

struct PresenceActionImpl: PresenceAction {
  var joins: [String: Presence]
  var leaves: [String: Presence]
  var rawMessage: _RealtimeMessage
}
