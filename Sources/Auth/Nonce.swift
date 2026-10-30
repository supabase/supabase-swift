import Crypto
import Foundation

/// Generates the nonce for an ID token sign-in.
///
/// A nonce ties an ID token to one sign-in attempt, so a stolen token cannot be replayed. Pass
/// `hashed` to the identity provider when you request the token, and `raw` to
/// ``IDTokenCredentials/nonce``. The server hashes `raw` and compares the result with the token's
/// `nonce` claim.
///
/// ```swift
/// let nonce = Nonce.generate()
///
/// let request = ASAuthorizationAppleIDProvider().createRequest()
/// request.nonce = nonce.hashed
/// // ...
/// try await client.auth.signInWithIDToken(
///   IDTokenCredentials(provider: .apple, idToken: idToken, nonce: nonce.raw)
/// )
/// ```
public enum Nonce {
  /// Returns a new random nonce and its SHA-256 hash.
  ///
  /// - Returns: `raw`, 32 random bytes in URL-safe Base64, and `hashed`, the lowercase hex SHA-256
  ///   of `raw`.
  public static func generate() -> (raw: String, hashed: String) {
    let raw = Data([UInt8].random(count: 32)).pkceBase64EncodedString()
    return (raw, sha256Hex(raw))
  }

  static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
