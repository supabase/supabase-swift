//
//  JWT.swift
//  Supabase
//
//  Created by Guilherme Souza on 28/11/24.
//

import Foundation

package struct DecodedJWT {
  package let header: [String: Any]
  package let payload: [String: Any]
  package let signature: Data
  package let raw: (header: String, payload: String)
}

package enum JWT {
  package static func decodePayload(_ jwt: String) -> [String: Any]? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else {
      return nil
    }

    let payload = String(parts[1])
    guard let data = Base64URL.decode(payload) else {
      return nil
    }
    let json = try? JSONSerialization.jsonObject(with: data, options: [])
    guard let decodedPayload = json as? [String: Any] else {
      return nil
    }
    return decodedPayload
  }

  package static func decode(_ jwt: String) -> DecodedJWT? {
    let parts = jwt.split(separator: ".")
    guard parts.count == 3 else {
      return nil
    }

    let headerString = String(parts[0])
    let payloadString = String(parts[1])
    let signatureString = String(parts[2])

    guard
      let headerData = Base64URL.decode(headerString),
      let payloadData = Base64URL.decode(payloadString),
      let signatureData = Base64URL.decode(signatureString),
      let headerJSON = try? JSONSerialization.jsonObject(with: headerData, options: []) as? [String: Any],
      let payloadJSON = try? JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any]
    else {
      return nil
    }

    return DecodedJWT(
      header: headerJSON,
      payload: payloadJSON,
      signature: signatureData,
      raw: (header: headerString, payload: payloadString)
    )
  }
}
