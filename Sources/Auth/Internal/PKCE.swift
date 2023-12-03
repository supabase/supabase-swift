import Crypto
import Foundation

enum PKCE {
  static func generateCodeVerifier() -> String {
    let buffer = [UInt8].random(count: 64)
    return Data(buffer).pkceBase64EncodedString()
  }

  static func generateCodeChallenge(from string: String) -> String {
    guard let data = string.data(using: .utf8) else {
      preconditionFailure("provided string should be utf8 encoded.")
    }

    var hasher = SHA256()
    hasher.update(data: data)
    let hashed = hasher.finalize()
    return Data(hashed).pkceBase64EncodedString()
  }
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
