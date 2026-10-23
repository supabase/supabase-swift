//
//  SupabaseFrameCodec.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers
import Phoenix

/// Thrown errors are ``SupabaseFrameError`` values with fixed descriptions, because the socket
/// logs them and a payload must never reach the log.
///
/// A binary kind 4 frame reaches the channel whole, under the `broadcast` event. Phoenix reads
/// `phx_close` and `phx_error` as control events, so a peer's event name must never become the
/// message event.
struct SupabaseFrameCodec: FrameCodec {
  /// The same limit Phoenix applies to text frames.
  static let maxNestingDepth = 64

  private let phoenix = PhoenixFrameCodec()

  func encode(_ frame: OutboundFrame) throws -> TransportFrame {
    guard frame.event == ChannelEvent.broadcast, case .binary(let template) = frame.payload else {
      return try phoenix.encode(frame)
    }
    do {
      return .binary(
        try BroadcastFrameCodec.stamp(template, joinRef: frame.joinRef, ref: frame.ref))
    } catch {
      throw SupabaseFrameError.malformedBroadcastPush
    }
  }

  func decode(_ frame: TransportFrame) throws -> InboundFrame {
    guard case .binary(let data) = frame,
      data.first == BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue
    else {
      return try phoenix.decode(frame)
    }
    if Self.jsonNestsTooDeep(kind4: data) {
      throw SupabaseFrameError.nestedTooDeep
    }
    let broadcast: DecodedBroadcast
    do {
      broadcast = try BroadcastFrameCodec.decode(data)
    } catch {
      throw SupabaseFrameError.malformedBroadcast
    }
    switch broadcast.payload {
    case .json(let payload):
      var envelope: Helpers.JSONObject = [
        "type": "broadcast",
        "event": .string(broadcast.event),
        "payload": .object(payload),
      ]
      envelope["meta"] = broadcast.meta.map(Helpers.JSONValue.object)
      return InboundFrame(
        joinRef: nil, ref: nil, topic: Topic(broadcast.topic),
        body: .message(ChannelEvent.broadcast, .json(.object(envelope.phoenix))))
    case .binary:
      return InboundFrame(
        joinRef: nil, ref: nil, topic: Topic(broadcast.topic),
        body: .message(ChannelEvent.broadcast, .binary(data)))
    }
  }
}

extension SupabaseFrameCodec {
  static func jsonNestsTooDeep(kind4 data: Data) -> Bool {
    let bytes = [UInt8](data)
    guard bytes.count >= 5 else { return false }
    let metaStart = 5 + Int(bytes[1]) + Int(bytes[2])
    let payloadStart = metaStart + Int(bytes[3])
    guard payloadStart <= bytes.count else { return false }
    let isJSONPayload = bytes[4] == BroadcastFrameCodec.PayloadEncoding.json.rawValue
    return JSONNesting.exceeds(maxNestingDepth, in: bytes[metaStart..<payloadStart])
      || (isJSONPayload && JSONNesting.exceeds(maxNestingDepth, in: bytes[payloadStart...]))
  }
}

enum SupabaseFrameError: Error, CustomStringConvertible {
  case malformedBroadcastPush
  case malformedBroadcast
  case nestedTooDeep

  var description: String {
    switch self {
    case .malformedBroadcastPush: "The client could not encode a broadcast frame."
    case .malformedBroadcast: "A binary broadcast frame does not follow the kind 4 format."
    case .nestedTooDeep:
      "A binary broadcast nests JSON deeper than \(SupabaseFrameCodec.maxNestingDepth) levels."
    }
  }
}

/// `JSONValue` decodes recursively, so a deep enough document would overflow a cooperative thread's stack before the decoder could reject it.
enum JSONNesting {
  static func exceeds(_ limit: Int, in bytes: some Collection<UInt8>) -> Bool {
    var depth = 0
    var inString = false
    var escaped = false
    for byte in bytes {
      if inString {
        if escaped {
          escaped = false
        } else if byte == UInt8(ascii: "\\") {
          escaped = true
        } else if byte == UInt8(ascii: "\"") {
          inString = false
        }
        continue
      }
      switch byte {
      case UInt8(ascii: "\""): inString = true
      case UInt8(ascii: "["), UInt8(ascii: "{"):
        depth += 1
        if depth > limit { return true }
      case UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
      default: break
      }
    }
    return false
  }
}
