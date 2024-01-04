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
@_spi(Internal) import _Helpers

/// Data that is received from the Server.
public struct RealtimeMessage {
  /// Reference number. Empty if missing
  public let ref: String

  /// Join Reference number
  let joinRef: String?

  /// Message topic
  public let topic: String

  /// Message event
  public let event: String

  /// The raw payload from the Message, including a nested response from
  /// phx_reply events. It is recommended to use `payload` instead.
  let rawPayload: Payload

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
    (rawPayload["status"] as? String).flatMap(PushStatus.init(rawValue:))
  }

  init(
    ref: String = "",
    topic: String = "",
    event: String = "",
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

    if let topic = json[2] as? String,
       let event = json[3] as? String,
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

public struct RealtimeMessageV2: Hashable, Codable, Sendable {
  public let joinRef: String?
  public let ref: String?
  public let topic: String
  public let event: String
  public let payload: JSONObject

  public init(joinRef: String?, ref: String?, topic: String, event: String, payload: JSONObject) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  public var eventType: EventType? {
    switch event {
    case ChannelEvent.system where payload["status"]?.stringValue == "ok": return .system
    case ChannelEvent.postgresChanges:
      return .postgresChanges
    case ChannelEvent.broadcast:
      return .broadcast
    case ChannelEvent.close:
      return .close
    case ChannelEvent.error:
      return .error
    case ChannelEvent.presenceDiff:
      return .presenceDiff
    case ChannelEvent.presenceState:
      return .presenceState
    case ChannelEvent.system
      where payload["message"]?.stringValue?.contains("access token has expired") == true:
      return .tokenExpired
    case ChannelEvent.reply:
      return .reply
    default:
      return nil
    }
  }

  public enum EventType {
    case system
    case postgresChanges
    case broadcast
    case close
    case error
    case presenceDiff
    case presenceState
    case tokenExpired
    case reply
  }

  private enum CodingKeys: String, CodingKey {
    case joinRef = "join_ref"
    case ref
    case topic
    case event
    case payload
  }
}

extension RealtimeMessageV2: HasRawMessage {
  public var rawMessage: RealtimeMessageV2 { self }
}
