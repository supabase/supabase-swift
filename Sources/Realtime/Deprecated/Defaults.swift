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

  /// Default maximum amount of time which the system may delay heartbeat events in order to
  /// minimize power usage
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

  /// Default encode function, utilizing JSONSerialization.data
  public static let encode: (Any) -> Data = { json in
    try! JSONSerialization
      .data(
        withJSONObject: json,
        options: JSONSerialization.WritingOptions()
      )
  }

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
    label: "com.phoenix.socket.heartbeat"
  )
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
/// a channel regarding a Channel's lifecycle.
public enum ChannelEvent {
  public static let join = "phx_join"
  public static let leave = "phx_leave"
  public static let close = "phx_close"
  public static let error = "phx_error"
  public static let reply = "phx_reply"
  public static let system = "system"
  public static let broadcast = "broadcast"
  public static let accessToken = "access_token"
  public static let presence = "presence"
  public static let presenceDiff = "presence_diff"
  public static let presenceState = "presence_state"
  public static let postgresChanges = "postgres_changes"

  public static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
