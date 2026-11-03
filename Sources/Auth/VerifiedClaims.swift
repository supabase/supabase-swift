public import Foundation
import Helpers

/// The claims of a JSON Web Token that ``AuthClient/claims(options:)`` or
/// ``AuthClient/claims(jwt:options:)`` verified.
///
/// Registered and Supabase claims have typed properties. Every other claim, such as one that a
/// custom access token hook adds, is in ``additionalClaims``.
public struct VerifiedClaims: Sendable, Hashable {
  /// The subject (`sub` claim), which is the user's ID.
  public let subject: String

  /// The issuer (`iss` claim), which is the URL of the Auth server that issued the token.
  public let issuer: String?

  /// The audience (`aud` claim). A single string audience becomes a one-element array, and an
  /// absent claim becomes an empty array.
  public let audience: [String]

  /// The expiration time (`exp` claim).
  public let expiresAt: Date

  /// The time the token was issued (`iat` claim).
  public let issuedAt: Date?

  /// The Postgres role of the token (`role` claim), for example `"authenticated"`.
  public let role: String?

  /// The user's email address (`email` claim).
  public let email: String?

  /// The user's phone number (`phone` claim).
  public let phone: String?

  /// The Authenticator Assurance Level of the session (`aal` claim), `"aal1"` or `"aal2"`.
  public let assuranceLevel: String?

  /// The authentication methods of the session (`amr` claim). A bare method string has no time
  /// of its own, so its entry takes the token's `iat`.
  public let amr: [AMREntry]

  /// The ID of the session that the token belongs to (`session_id` claim).
  public let sessionID: String?

  /// Whether the user signed in anonymously (`is_anonymous` claim).
  public let isAnonymous: Bool?

  /// The user's app metadata (`app_metadata` claim). It is empty when the claim is absent.
  public let appMetadata: JSONObject

  /// The user's metadata (`user_metadata` claim). It is empty when the claim is absent.
  public let userMetadata: JSONObject

  /// Every claim that has no typed property in this type, keyed by its name in the token.
  public let additionalClaims: JSONObject

  /// The decoded header of the token.
  public let header: JWTHeader

  /// The raw signature bytes of the token.
  public let signature: Data
}

extension VerifiedClaims {
  private static let typedClaimNames: Set<String> = [
    "sub", "iss", "aud", "exp", "iat", "role", "email", "phone", "aal", "amr", "session_id",
    "is_anonymous", "app_metadata", "user_metadata",
  ]

  init(_ jwt: DecodedJWT) throws {
    let payload = try Self.decodeSegment(JSONObject.self, from: jwt.raw.payload)

    guard let expiresAt = payload["exp"].flatMap(Self.timeInterval) else {
      throw AuthError.jwtVerificationFailed("JWT is missing the exp claim")
    }
    guard let subject = payload["sub"]?.stringValue else {
      throw AuthError.jwtVerificationFailed("JWT is missing the sub claim")
    }
    let issuedAt = payload["iat"].flatMap(Self.timeInterval)

    self.subject = subject
    self.issuer = payload["iss"]?.stringValue
    self.audience = Self.audience(from: payload["aud"])
    self.expiresAt = Date(timeIntervalSince1970: expiresAt)
    self.issuedAt = issuedAt.map(Date.init(timeIntervalSince1970:))
    self.role = payload["role"]?.stringValue
    self.email = payload["email"]?.stringValue
    self.phone = payload["phone"]?.stringValue
    self.assuranceLevel = payload["aal"]?.stringValue
    self.amr =
      (jwt.payload["amr"] as? [Any])?.compactMap { AMREntry(value: $0, issuedAt: issuedAt) } ?? []
    self.sessionID = payload["session_id"]?.stringValue
    self.isAnonymous = payload["is_anonymous"]?.boolValue
    self.appMetadata = payload["app_metadata"]?.objectValue ?? [:]
    self.userMetadata = payload["user_metadata"]?.objectValue ?? [:]
    self.additionalClaims = payload.filter { !Self.typedClaimNames.contains($0.key) }
    self.header = try Self.decodeSegment(JWTHeader.self, from: jwt.raw.header)
    self.signature = jwt.signature
  }

  private static func decodeSegment<T: Decodable>(_ type: T.Type, from segment: String) throws -> T
  {
    guard
      let data = Base64URL.decode(segment),
      let value = try? JSONDecoder().decode(T.self, from: data)
    else {
      throw AuthError.jwtVerificationFailed("Invalid JWT structure")
    }
    return value
  }

  private static func timeInterval(_ value: JSONValue) -> TimeInterval? {
    switch value {
    case .integer(let seconds): TimeInterval(seconds)
    case .double(let seconds): seconds
    default: nil
    }
  }

  private static func audience(from value: JSONValue?) -> [String] {
    switch value {
    case .string(let audience): [audience]
    case .array(let audiences): audiences.compactMap(\.stringValue)
    default: []
    }
  }
}

/// Options for ``AuthClient/claims(options:)`` and ``AuthClient/claims(jwt:options:)``.
public struct ClaimsOptions: Sendable, Hashable {
  /// Whether to return the claims of an expired token. When `false`, an expired token fails
  /// verification.
  ///
  /// It applies only to tokens that the client verifies on the device. The Auth server rejects an
  /// expired token that it verifies, so ``AuthClient/claims(jwt:options:)`` still throws for that
  /// token.
  public var allowsExpired: Bool

  /// A key set to verify the token with. It takes precedence over the key set that the client
  /// fetches from the Auth server.
  ///
  /// The client checks this key set first. When it has no key with the token's `kid`, the client
  /// uses the key set from the Auth server.
  public var jwks: JWKS?

  /// Creates claims options.
  ///
  /// - Parameters:
  ///   - allowsExpired: Pass `true` to return the claims of an expired token that the client
  ///     verifies on the device.
  ///   - jwks: A key set to check first. When it has no key with the token's `kid`, the client
  ///     uses the key set from the Auth server.
  public init(allowsExpired: Bool = false, jwks: JWKS? = nil) {
    self.allowsExpired = allowsExpired
    self.jwks = jwks
  }
}
