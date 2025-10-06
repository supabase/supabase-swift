//
//  Base64URL.swift
//  Supabase
//
//  Created by Claude on 06/10/25.
//

import Foundation

package enum Base64URL {
  /// Decodes a base64url-encoded string to Data
  package static func decode(_ value: String) -> Data? {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let length = Double(base64.lengthOfBytes(using: .utf8))
    let requiredLength = 4 * ceil(length / 4.0)
    let paddingLength = requiredLength - length
    if paddingLength > 0 {
      let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
      base64 = base64 + padding
    }
    return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
  }

  /// Encodes Data to a base64url-encoded string
  package static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
