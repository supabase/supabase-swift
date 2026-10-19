import Crypto
import Foundation

struct PKCE {
  var generateCodeVerifier: @Sendable () -> String
  var generateCodeChallenge: @Sendable (_ codeVerifier: String) -> String
}

extension PKCE {
  static let live = PKCE(
    generateCodeVerifier: {
      let buffer = [UInt8].random(count: 64)
      return Data(buffer).pkceBase64EncodedString()
    },
    generateCodeChallenge: { codeVerifier in
      var hasher = SHA256()
      hasher.update(data: Data(codeVerifier.utf8))
      let hashed = hasher.finalize()
      return Data(hashed).pkceBase64EncodedString()
    }
  )
}

extension Data {
  func pkceBase64EncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
      .trimmingCharacters(in: .whitespaces)
  }
}
