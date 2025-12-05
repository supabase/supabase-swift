//
//  RealtimeSerializer.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation

/// Protocol for encoding and decoding Realtime messages.
protocol RealtimeSerializer: Sendable {
  /// Encodes a message for sending over the WebSocket connection.
  /// - Parameter message: The message to encode
  /// - Returns: Either Data (for binary encoding) or String (for JSON encoding)
  func encode(_ message: RealtimeMessageV2) throws -> Any

  /// Decodes a message received from the WebSocket connection.
  /// - Parameter data: Either Data (binary) or String (JSON)
  /// - Returns: The decoded message
  func decode(_ data: Any) throws -> RealtimeMessageV2
}
