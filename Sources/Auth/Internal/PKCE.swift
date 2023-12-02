#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif
import Foundation

enum PKCE {
  static func generateCodeVerifier() -> String {
    #if canImport(CryptoKit)
    var buffer = [UInt8](repeating: 0, count: 64)
    _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
    return Data(buffer).pkceBase64EncodedString()
    #elseif canImport(Crypto)
    var buffer = Data(repeating: 0, count: 64)
    return Data(buffer).pkceBase64EncodedString()
    #endif

    return ""
  }

  static func generateCodeChallenge(from string: String) -> String {
    guard let data = string.data(using: .utf8) else {
      preconditionFailure("provided string should be utf8 encoded.")
    }

    #if canImport(CryptoKit)
    let hashed = SHA256.hash(data: data)
    return Data(hashed).pkceBase64EncodedString()
    #elseif canImport(Crypto)
    var hasher = SHA256()
    hasher.update(data: data)
    let hashed = hasher.finalize()
    return Data(hashed).pkceBase64EncodedString()
    #endif

    return ""
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
