//
//  JWTVerifier.swift
//  Supabase
//
//  Created by Claude on 06/10/25.
//

import Foundation

enum JWTAlgorithm: String {
  case rs256 = "RS256"

  func verify(
    jwt: DecodedJWT,
    jwk: JWK
  ) -> Bool {
    let message = "\(jwt.raw.header).\(jwt.raw.payload)".data(using: .utf8)!
    switch self {
    case .rs256:
      return SecKeyVerifySignature(
        jwk.rsaPublishKey!,
        .rsaSignatureMessagePKCS1v15SHA256,
        message as CFData,
        jwt.signature as CFData,
        nil
      )
    }
  }
}
