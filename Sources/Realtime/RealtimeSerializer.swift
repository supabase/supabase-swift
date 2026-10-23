//
//  RealtimeSerializer.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import Foundation
import Helpers

/// Handles encoding/decoding between ``RealtimeMessageV2`` and the Realtime protocol 2.0.0 text
/// frames: `[joinRef, ref, topic, event, payload]`.
///
/// Broadcasts can arrive on either transport: as a text frame, or as a binary frame that
/// ``BroadcastFrameCodec`` decodes.
package struct RealtimeSerializer: Sendable {
  package init() {}

  /// Encodes a ``RealtimeMessageV2`` as a JSON array string: `[joinRef, ref, topic, event, payload]`.
  package func encodeText(_ message: RealtimeMessageV2) throws -> String {
    let array: [JSONValue] = [
      message.joinRef.map { .string($0) } ?? .null,
      message.ref.map { .string($0) } ?? .null,
      .string(message.topic),
      .string(message.event),
      .object(message.payload),
    ]

    let data = try JSONEncoder().encode(array)
    return String(decoding: data, as: UTF8.self)
  }

  /// Decodes a JSON array string `[joinRef, ref, topic, event, payload]` into a ``RealtimeMessageV2``.
  package func decodeText(_ text: String) throws -> RealtimeMessageV2 {
    let data = Data(text.utf8)
    let array = try JSONDecoder().decode([JSONValue].self, from: data)

    guard array.count == 5 else {
      throw RealtimeError.decoding(
        "Expected JSON array with 5 elements, got \(array.count)."
      )
    }

    let joinRef = array[0].stringValue
    let ref = array[1].stringValue
    guard let topic = array[2].stringValue else {
      throw RealtimeError.decoding("Expected string for topic at index 2.")
    }
    guard let event = array[3].stringValue else {
      throw RealtimeError.decoding("Expected string for event at index 3.")
    }
    guard let payload = array[4].objectValue else {
      throw RealtimeError.decoding("Expected object for payload at index 4.")
    }

    return RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: payload
    )
  }
}
