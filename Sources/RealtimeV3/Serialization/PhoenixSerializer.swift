//
//  PhoenixSerializer.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation
import Helpers

/// Handles encoding/decoding between `PhoenixMessage` and the Phoenix protocol 2.0.0 wire format.
///
/// Text frames use a JSON array format: `[joinRef, ref, topic, event, payload]`.
struct PhoenixSerializer: Sendable {

  // MARK: - Text encoding (JSON array format)

  /// Encodes a Phoenix message as a JSON array string: `[joinRef, ref, topic, event, payload]`.
  func encodeText(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    payload: JSONObject
  ) throws -> String {
    let array: [AnyJSON] = [
      joinRef.map { .string($0) } ?? .null,
      ref.map { .string($0) } ?? .null,
      .string(topic),
      .string(event),
      .object(payload),
    ]

    let data: Data
    do {
      data = try JSONEncoder().encode(array)
    } catch {
      throw RealtimeError.encoding(underlying: error)
    }

    guard let text = String(data: data, encoding: .utf8) else {
      struct UTF8EncodingError: Error & Sendable {
        let message = "Failed to encode message as UTF-8 string."
      }
      throw RealtimeError.encoding(underlying: UTF8EncodingError())
    }
    return text
  }

  // MARK: - Text decoding (JSON array format)

  /// Decodes a JSON array string `[joinRef, ref, topic, event, payload]` into a `PhoenixMessage`.
  func decodeText(_ text: String, receivedAt: Date) throws -> PhoenixMessage {
    struct StructuralError: Error & Sendable {
      let message: String
    }

    let data = Data(text.utf8)
    let array: [AnyJSON]
    do {
      array = try JSONDecoder().decode([AnyJSON].self, from: data)
    } catch {
      throw RealtimeError.decoding(type: "PhoenixMessage", underlying: error)
    }

    guard array.count >= 5 else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(
          message: "Expected JSON array with 5 elements, got \(array.count)."
        )
      )
    }

    let joinRef = array[0].stringValue
    let ref = array[1].stringValue

    guard let topic = array[2].stringValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected string for topic at index 2.")
      )
    }
    guard let event = array[3].stringValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected string for event at index 3.")
      )
    }
    guard let payloadObject = array[4].objectValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected object for payload at index 4.")
      )
    }

    return PhoenixMessage(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: .json(.object(payloadObject)),
      receivedAt: receivedAt
    )
  }
}
