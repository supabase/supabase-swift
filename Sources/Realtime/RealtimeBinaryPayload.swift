//
//  RealtimeBinaryPayload.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation

/// Helper for creating and working with binary payloads in Realtime messages.
public enum RealtimeBinaryPayload {
  /// Creates a JSON payload marker for binary data.
  /// This can be used in `RealtimeMessageV2.payload` to indicate binary data.
  ///
  /// - Parameter data: The binary data to encode
  /// - Returns: An AnyJSON object representing the binary data
  public static func binary(_ data: Data) -> AnyJSON {
    .object([
      "__binary__": .bool(true),
      "data": .string(data.base64EncodedString()),
    ])
  }

  /// Checks if a JSON value represents binary data.
  /// - Parameter value: The AnyJSON value to check
  /// - Returns: true if the value represents binary data
  public static func isBinary(_ value: AnyJSON) -> Bool {
    guard case .object(let obj) = value,
      let isBinary = obj["__binary__"]?.boolValue
    else {
      return false
    }
    return isBinary
  }

  /// Extracts binary data from a JSON value.
  /// - Parameter value: The AnyJSON value containing binary data
  /// - Returns: The decoded binary data, or nil if not a binary payload
  public static func data(from value: AnyJSON) -> Data? {
    guard case .object(let obj) = value,
      let isBinary = obj["__binary__"]?.boolValue,
      isBinary,
      let base64String = obj["data"]?.stringValue,
      let data = Data(base64Encoded: base64String)
    else {
      return nil
    }
    return data
  }
}
