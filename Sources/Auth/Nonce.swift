import Crypto
import Foundation

/// A nonce for an ID token sign-in.
///
/// A nonce ties an ID token to one sign-in attempt, so a stolen token cannot be replayed. Pass
/// ``hashed`` to the identity provider when you request the token, and ``raw`` to
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
public struct Nonce: Sendable, Hashable {
  /// 32 random bytes in URL-safe Base64. Pass it to ``IDTokenCredentials/nonce``.
  public let raw: String

  /// The lowercase hex SHA-256 of ``raw``. Pass it to the identity provider.
  public let hashed: String

  init(raw: String) {
    self.raw = raw
    self.hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Returns a new random nonce.
  public static func generate() -> Nonce {
    Nonce(raw: Data([UInt8].random(count: 32)).pkceBase64EncodedString())
  }
}
