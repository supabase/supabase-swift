//
//  PhoenixMessage.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/26.
//

import Foundation

/// Decoded Phoenix protocol message (text array format or binary broadcast).
struct PhoenixMessage: Sendable {
  var joinRef: String?
  var ref: String?
  var topic: String
  var event: String
  var payload: [String: JSONValue]
}

/// Decoded server-to-client binary broadcast (type 0x04).
struct BinaryBroadcast: Sendable {
  let topic: String
  let event: String
  enum Payload: Sendable {
    case json([String: JSONValue])
    case binary(Data)
  }
  let payload: Payload
}
