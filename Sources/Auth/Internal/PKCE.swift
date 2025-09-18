import Crypto
import Foundation

struct PKCE {
  var generateCodeVerifier: @Sendable () -> String
  var generateCodeChallenge: @Sendable (_ codeVerifier: String) -> String
  var validateCodeVerifier: @Sendable (_ codeVerifier: String) -> Bool
  var validateCodeChallenge: @Sendable (_ codeChallenge: String) -> Bool
}

extension PKCE {
  static let live = PKCE(
    generateCodeVerifier: {
      let buffer = [UInt8].random(count: 64)
      return Data(buffer).pkceBase64EncodedString()
    },
    generateCodeChallenge: { codeVerifier in
      guard let data = codeVerifier.data(using: .utf8) else {
        preconditionFailure("provided string should be utf8 encoded.")
      }

      var hasher = SHA256()
      hasher.update(data: data)
      let hashed = hasher.finalize()
      return Data(hashed).pkceBase64EncodedString()
    },
    validateCodeVerifier: { codeVerifier in
      // PKCE code verifier must be 43-128 characters long
      guard codeVerifier.count >= 43 && codeVerifier.count <= 128 else {
        return false
      }
      
      // Must contain only unreserved characters: A-Z, a-z, 0-9, -, ., _, ~
      let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
      return codeVerifier.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    },
    validateCodeChallenge: { codeChallenge in
      // PKCE code challenge must be 43 characters long (SHA256 hash)
      guard codeChallenge.count == 43 else {
        return false
      }
      
      // Must contain only unreserved characters: A-Z, a-z, 0-9, -, ., _, ~
      let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
      return codeChallenge.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
  )
}

extension Data {
  // Returns a base64 encoded string, replacing reserved characters
  // as per the PKCE spec https://tools.ietf.org/html/rfc7636#section-4.2
  func pkceBase64EncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
      .trimmingCharacters(in: .whitespaces)
  }
}
