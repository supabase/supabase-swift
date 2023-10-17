// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

/// A collection of default values and behaviors used across the Client
public enum Defaults {
  /// Default timeout when sending messages
  public static let timeoutInterval: TimeInterval = 10.0

  /// Default interval to send heartbeats on
  public static let heartbeatInterval: TimeInterval = 30.0

  /// Default maximum amount of time which the system may delay heartbeat events in order to minimize power usage
  public static let heartbeatLeeway: DispatchTimeInterval = .milliseconds(10)

  /// Default reconnect algorithm for the socket
  public static let reconnectSteppedBackOff: (Int) -> TimeInterval = { tries in
    tries > 9 ? 5.0 : [0.01, 0.05, 0.1, 0.15, 0.2, 0.25, 0.5, 1.0, 2.0][tries - 1]
  }

  /** Default rejoin algorithm for individual channels */
  public static let rejoinSteppedBackOff: (Int) -> TimeInterval = { tries in
    tries > 3 ? 10 : [1, 2, 5][tries - 1]
  }

  public static let vsn = "2.0.0"

  /// Default encoder
  public static let encoder: JSONEncoder = JSONEncoder()

  /// Default encode function, utilizing JSONSerialization.data
  public static let encode: (Any) -> Data = { json in
    assert(JSONSerialization.isValidJSONObject(json), "Invalid JSON object")
    return
      try! JSONSerialization
      .data(
        withJSONObject: json,
        options: JSONSerialization.WritingOptions()
      )
  }

  /// Default decoder
  public static let decoder: JSONDecoder = JSONDecoder()

  /// Default decode function, utilizing JSONSerialization.jsonObject
  public static let decode: (Data) -> Any? = { data in
    guard
      let json =
        try? JSONSerialization
        .jsonObject(
          with: data,
          options: JSONSerialization.ReadingOptions()
        )
    else { return nil }
    return json
  }

  public static let heartbeatQueue: DispatchQueue = .init(
    label: "com.phoenix.socket.heartbeat")
}

/// Represents the multiple states that a Channel can be in
/// throughout it's lifecycle.
public enum ChannelState: String {
  case closed
  case errored
  case joined
  case joining
  case leaving
}

/// Represents the different events that can be sent through
/// a channel regarding a Channel's lifecycle or
/// that can be registered to be notified of.
public enum ChannelEvent: RawRepresentable {
  public enum Presence: String {
    case state
    case diff
  }

  case heartbeat
  case join
  case leave
  case reply
  case error
  case close

  case all
  case insert
  case update
  case delete

  case channelReply(String)

  case broadcast

  case presence
  case presenceState
  case presenceDiff

  public var rawValue: String {
    switch self {
    case .heartbeat: return "heartbeat"
    case .join: return "phx_join"
    case .leave: return "phx_leave"
    case .reply: return "phx_reply"
    case .error: return "phx_error"
    case .close: return "phx_close"

    case .all: return "*"
    case .insert: return "insert"
    case .update: return "update"
    case .delete: return "delete"

    case let .channelReply(reference): return "chan_reply_\(reference)"

    case .broadcast: return "broadcast"

    case .presence: return "presence"
    case .presenceState: return "presence_state"
    case .presenceDiff: return "presence_diff"
    }
  }

  public init?(rawValue: String) {
    switch rawValue.lowercased() {
    case "heartbeat": self = .heartbeat
    case "phx_join": self = .join
    case "phx_leave": self = .leave
    case "phx_reply": self = .reply
    case "phx_error": self = .error
    case "phx_close": self = .close
    case "*": self = .all
    case "insert": self = .insert
    case "update": self = .update
    case "delete": self = .delete
    case "broadcast": self = .broadcast
    case "presence": self = .presence
    case "presence_state": self = .presenceState
    case "presence_diff": self = .presenceDiff
    default: return nil
    }
  }

  var isLifecyleEvent: Bool {
    switch self {
    case .join, .leave, .reply, .error, .close: return true
    default: return false
    }
  }
}

/// Represents the different topic a channel can subscribe to.
public enum ChannelTopic: RawRepresentable, Equatable {
  case all
  case schema(_ schema: String)
  case table(_ table: String, schema: String)
  case column(_ column: String, value: String, table: String, schema: String)

  case heartbeat

  public var rawValue: String {
    switch self {
    case .all: return "realtime:*"
    case let .schema(name): return "realtime:\(name)"
    case let .table(tableName, schema): return "realtime:\(schema):\(tableName)"
    case let .column(columnName, value, table, schema):
      return "realtime:\(schema):\(table):\(columnName)=eq.\(value)"
    case .heartbeat: return "phoenix"
    }
  }

  public init?(rawValue: String) {
    if rawValue == "realtime:*" || rawValue == "*" {
      self = .all
    } else if rawValue == "phoenix" {
      self = .heartbeat
    } else {
      let parts = rawValue.replacingOccurrences(of: "realtime:", with: "").split(separator: ":")
      switch parts.count {
      case 1:
        self = .schema(String(parts[0]))
      case 2:
        self = .table(String(parts[1]), schema: String(parts[0]))
      case 3:
        let condition = parts[2].split(separator: "=")
        if condition.count == 2,
          condition[1].hasPrefix("eq.")
        {
          self = .column(
            String(condition[0]), value: String(condition[1].dropFirst(3)), table: String(parts[1]),
            schema: String(parts[0])
          )
        } else {
          return nil
        }
      default:
        return nil
      }
    }
  }
}

/// Represents the broadcast and presence options for a channel.
public struct ChannelOptions {
  /// Used to track presence payload across clients. Must be unique per client. If `nil`, the server will generate one.
  var presenceKey: String?
  /// Enables the client to receieve their own`broadcast` messages
  var broadcastSelf: Bool
  /// Instructs the server to acknoledge the client's `broadcast` messages
  var broadcastAcknowledge: Bool

  public init(
    presenceKey: String? = nil, broadcastSelf: Bool = false, broadcastAcknowledge: Bool = false
  ) {
    self.presenceKey = presenceKey
    self.broadcastSelf = broadcastSelf
    self.broadcastAcknowledge = broadcastAcknowledge
  }

  /// Parameters used to configure the channel
  var params: [String: [String: Any]] {
    [
      "config": [
        "presence": [
          "key": presenceKey ?? ""
        ],
        "broadcast": [
          "ack": broadcastAcknowledge,
          "self": broadcastSelf,
        ],
      ]
    ]
  }

}

/// Represents the different status of a push
public enum PushStatus: String {
  case ok
  case error
  case timeout
}
