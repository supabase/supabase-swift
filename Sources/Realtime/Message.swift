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
public struct Message: Sendable, Hashable {
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
    rawPayload["response"]?.objectValue ?? rawPayload
  }

  /// Convenience accessor. Equivalent to getting the status as such:
  /// ```swift
  /// message.payload["status"]
  /// ```
  public var status: PushStatus? {
    rawPayload["status"]?.stringValue.flatMap(PushStatus.init(rawValue:))
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
}

extension Message: Decodable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()

    let joinRef = try container.decodeIfPresent(String.self)
    let ref = try container.decodeIfPresent(String.self)
    let topic = try container.decode(String.self)
    let event = try container.decode(String.self)
    let payload = try container.decode(Payload.self)
    self.init(
      ref: ref ?? "",
      topic: topic,
      event: event,
      payload: payload,
      joinRef: joinRef
    )
  }
}

extension Message: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()

    if let joinRef {
      try container.encode(joinRef)
    } else {
      try container.encodeNil()
    }

    try container.encode(ref)
    try container.encode(topic)
    try container.encode(event)
    try container.encode(payload)
  }
}
