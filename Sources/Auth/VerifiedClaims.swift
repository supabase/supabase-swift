public import Foundation
import Helpers

/// The claims of a JSON Web Token that ``AuthClient/claims(options:)`` or
/// ``AuthClient/claims(jwt:options:)`` verified.
///
/// Registered and Supabase claims have typed properties. Every other claim, such as one that a
/// custom access token hook adds, is in ``additionalClaims``.
///
/// - Note: The public initializer is for fixtures and previews. A value you build yourself did not
///   go through verification, so never treat it as proof that a token is valid.
public struct VerifiedClaims: Sendable, Hashable {
  /// The subject (`sub` claim), which is the user's ID.
  public var subject: String

  /// The issuer (`iss` claim), which is the URL of the Auth server that issued the token.
  public var issuer: String?

  /// The audience (`aud` claim). A single string audience becomes a one-element array, and an
  /// absent claim becomes an empty array.
  public var audience: [String]

  /// The expiration time (`exp` claim).
  public var expiresAt: Date

  /// The time the token was issued (`iat` claim).
  public var issuedAt: Date?

  /// The time before which the token is not valid (`nbf` claim).
  public var notBefore: Date?

  /// The Postgres role of the token (`role` claim), for example `"authenticated"`.
  public var role: String?

  /// The user's email address (`email` claim).
  public var email: String?

  /// The user's phone number (`phone` claim).
  public var phone: String?

  /// The Authenticator Assurance Level of the session (`aal` claim).
  public var assuranceLevel: AuthenticatorAssuranceLevel?

  /// The authentication methods of the session (`amr` claim). A bare method string has no time
  /// of its own, so its entry takes the token's `iat`.
  public var amr: [AMREntry]

  /// The ID of the session that the token belongs to (`session_id` claim).
  public var sessionID: String?

  /// Whether the user signed in anonymously (`is_anonymous` claim).
  public var isAnonymous: Bool?

  /// The user's app metadata (`app_metadata` claim). It is empty when the claim is absent.
  public var appMetadata: JSONObject

  /// The user's metadata (`user_metadata` claim). It is empty when the claim is absent.
  public var userMetadata: JSONObject

  /// Every claim that has no typed property in this type, keyed by its name in the token.
  public var additionalClaims: JSONObject

  /// The decoded header of the token.
  public var header: JWTHeader

  /// The raw signature bytes of the token.
  public var signature: Data

  /// Creates a ``VerifiedClaims``.
  public init(
    subject: String,
    issuer: String? = nil,
    audience: [String],
    expiresAt: Date,
    issuedAt: Date? = nil,
    notBefore: Date? = nil,
    role: String? = nil,
    email: String? = nil,
    phone: String? = nil,
    assuranceLevel: AuthenticatorAssuranceLevel? = nil,
    amr: [AMREntry],
    sessionID: String? = nil,
    isAnonymous: Bool? = nil,
    appMetadata: JSONObject,
    userMetadata: JSONObject,
    additionalClaims: JSONObject,
    header: JWTHeader,
    signature: Data
  ) {
    self.subject = subject
    self.issuer = issuer
    self.audience = audience
    self.expiresAt = expiresAt
    self.issuedAt = issuedAt
    self.notBefore = notBefore
    self.role = role
    self.email = email
    self.phone = phone
    self.assuranceLevel = assuranceLevel
    self.amr = amr
    self.sessionID = sessionID
    self.isAnonymous = isAnonymous
    self.appMetadata = appMetadata
    self.userMetadata = userMetadata
    self.additionalClaims = additionalClaims
    self.header = header
    self.signature = signature
  }
}

extension VerifiedClaims {
  private static let typedClaimNames: Set<String> = [
    "sub", "iss", "aud", "exp", "iat", "nbf", "role", "email", "phone", "aal", "amr", "session_id",
    "is_anonymous", "app_metadata", "user_metadata",
  ]

  init(_ jwt: DecodedJWT) throws {
    let payload = try Self.decodeSegment(JSONObject.self, from: jwt.raw.payload)

    guard let expiresAt = payload["exp"]?.doubleValue else {
      throw AuthError.jwtVerificationFailed("JWT is missing the exp claim")
    }
    guard let subject = payload["sub"]?.stringValue else {
      throw AuthError.jwtVerificationFailed("JWT is missing the sub claim")
    }
    let issuedAt = payload["iat"]?.doubleValue
    let notBefore = payload["nbf"]?.doubleValue

    self.subject = subject
    self.issuer = payload["iss"]?.stringValue
    self.audience = Self.audience(from: payload["aud"])
    self.expiresAt = Date(timeIntervalSince1970: expiresAt)
    self.issuedAt = issuedAt.map(Date.init(timeIntervalSince1970:))
    self.notBefore = notBefore.map(Date.init(timeIntervalSince1970:))
    self.role = payload["role"]?.stringValue
    self.email = payload["email"]?.stringValue
    self.phone = payload["phone"]?.stringValue
    self.assuranceLevel = payload["aal"]?.stringValue.map(
      AuthenticatorAssuranceLevel.init(rawValue:))
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
