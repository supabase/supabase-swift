//
//  JWT.swift
//  Supabase
//
//  Created by Guilherme Souza on 28/11/24.
//

import Foundation

package enum JWT {
  package static func decodePayload(_ jwt: String) -> [String: Any]? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else {
      return nil
    }

    let payload = String(parts[1])
    guard let data = base64URLDecode(payload) else {
      return nil
    }
    let json = try? JSONSerialization.jsonObject(with: data, options: [])
    guard let decodedPayload = json as? [String: Any] else {
      return nil
    }
    return decodedPayload
  }

  private static func base64URLDecode(_ value: String) -> Data? {
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
}
