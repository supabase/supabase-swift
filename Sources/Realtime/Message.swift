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

/// Data that is received from the Server.
public class Message {
  /// Reference number. Empty if missing
  public let ref: String

  /// Join Reference number
  internal let joinRef: String?

  /// Message topic
  public let topic: ChannelTopic

  /// Message event
  public let event: ChannelEvent

  /// The raw payload from the Message, including a nested response from
  /// phx_reply events. It is recommended to use `payload` instead.
  internal let rawPayload: Payload

  /// Message payload
  public var payload: Payload {
    guard let response = rawPayload["response"] as? Payload
    else { return rawPayload }
    return response
  }

  /// Convenience accessor. Equivalent to getting the status as such:
  /// ```swift
  /// message.payload["status"]
  /// ```
  public var status: PushStatus? {
    guard let status = rawPayload["status"] as? String else {
      return nil
    }
    return PushStatus(rawValue: status)
  }

  init(
    ref: String = "",
    topic: ChannelTopic = .all,
    event: ChannelEvent = .all,
    payload: Payload = [:],
    joinRef: String? = nil
  ) {
    self.ref = ref
    self.topic = topic
    self.event = event
    rawPayload = payload
    self.joinRef = joinRef
  }

  init?(json: [Any?]) {
    guard json.count > 4 else { return nil }
    joinRef = json[0] as? String
    ref = json[1] as? String ?? ""

    if let topic = (json[2] as? String).flatMap(ChannelTopic.init(rawValue:)),
      let event = (json[3] as? String).flatMap(ChannelEvent.init(rawValue:)),
      let payload = json[4] as? Payload
    {
      self.topic = topic
      self.event = event
      rawPayload = payload
    } else {
      return nil
    }
  }
}
