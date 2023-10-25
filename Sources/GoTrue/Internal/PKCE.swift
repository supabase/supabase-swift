import CryptoKit
import Foundation

enum PKCE {
  static func generateCodeVerifier() -> String {
    var buffer = [UInt8](repeating: 0, count: 64)
    _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
    return Data(buffer).pkceBase64EncodedString()
  }

  static func generateCodeChallenge(from string: String) -> String {
    guard let data = string.data(using: .utf8) else {
      preconditionFailure("provided string should be utf8 encoded.")
    }
    let hashed = SHA256.hash(data: data)

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
