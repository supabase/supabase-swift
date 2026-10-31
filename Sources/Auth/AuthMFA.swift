public import Foundation

/// Contains the full multi-factor authentication API.
///
/// Access this namespace via ``AuthClient/mfa``.
///
/// ```swift
/// let enrollment = try await client.auth.mfa.enrollTOTP(friendlyName: "My phone")
/// // Show enrollment.qrCode, then ask the user for the code from their authenticator app.
/// try await client.auth.mfa.challengeAndVerify(factorID: enrollment.id, code: code)
/// ```
///
/// ## Topics
///
/// ### Enrolling factors
/// - ``enrollTOTP(issuer:friendlyName:)``
/// - ``enrollPhone(_:friendlyName:)``
/// - ``unenroll(factorID:)``
///
/// ### Verifying factors
/// - ``challenge(factorID:channel:)``
/// - ``verify(factorID:challengeID:code:)``
/// - ``challengeAndVerify(factorID:code:)``
///
/// ### Inspecting factors and the session
/// - ``factors()``
/// - ``assuranceLevel()``
///
/// ### Recovery codes
/// - ``recoveryCodes``
public struct AuthMFA: Sendable {
  let dependencies: Dependencies

  /// Contains all recovery code methods.
  public let recoveryCodes: AuthMFARecoveryCodes

  init(dependencies: Dependencies) {
    self.dependencies = dependencies
    self.recoveryCodes = AuthMFARecoveryCodes(dependencies: dependencies)
  }

  private var api: SessionAPIClient { dependencies.sessionAPI }
  private var authAPI: AuthAPI { dependencies.authAPI }
  private var sessionManager: SessionManager { dependencies.sessionManager }
  private var sessionStore: SessionStore { dependencies.sessionStore }

  /// Enrolls a new, `unverified` TOTP factor.
  ///
  /// Show ``TOTPEnrollment/qrCode`` or ``TOTPEnrollment/secret`` to the user and ask them to add
  /// it to their authenticator app. Then pass the code the app shows to
  /// ``challengeAndVerify(factorID:code:)`` to verify the factor.
  ///
  /// - Parameters:
  ///   - issuer: The domain the user enrolls with, shown in the authenticator app.
  ///   - friendlyName: A name that tells the factor apart from the user's other factors.
  /// - Returns: The new factor and the data the authenticator app needs.
  public func enrollTOTP(
    issuer: String? = nil,
    friendlyName: String? = nil
  ) async throws -> TOTPEnrollment {
    try await api.authorizedExecute {
      try authAPI.enrollFactor(
        .totp(issuer: issuer, friendlyName: friendlyName), decoding: TOTPEnrollment.self,
        accessToken: $0)
    }
  }

  /// Enrolls a new, `unverified` phone factor.
  ///
  /// Call ``challenge(factorID:channel:)`` to send a code to the phone, then pass that code to
  /// ``verify(factorID:challengeID:code:)`` to verify the factor.
  ///
  /// - Parameters:
  ///   - phone: The phone number, in E.164 format.
  ///   - friendlyName: A name that tells the factor apart from the user's other factors.
  /// - Returns: The new factor.
  public func enrollPhone(
    _ phone: String,
    friendlyName: String? = nil
  ) async throws -> PhoneEnrollment {
    try await api.authorizedExecute {
      try authAPI.enrollFactor(
        .phone(phone, friendlyName: friendlyName), decoding: PhoneEnrollment.self,
        accessToken: $0)
    }
  }

  /// Enrolls a new, `unverified` WebAuthn factor.
  ///
  /// Use it to drive the ceremony with your own authenticator. Otherwise, call
  /// `enrollWebAuthnFactor(friendlyName:presentationAnchor:)`.
  ///
  /// - Parameter friendlyName: A name that tells the factor apart from the user's other factors.
  /// - Returns: The ID of the new factor. Pass it to ``challenge(factorID:webAuthn:)``.
  @_spi(Experimental)
  public func enrollWebAuthn(friendlyName: String? = nil) async throws -> UUID {
    struct Enrollment: Decodable {
      let id: UUID
    }

    return try await api.authorizedExecute {
      try authAPI.enrollFactor(
        .webAuthn(friendlyName: friendlyName), decoding: Enrollment.self, accessToken: $0)
    }.id
  }

  /// Creates a challenge for a factor. For a phone factor, this sends the code.
  ///
  /// - Parameters:
  ///   - factorID: The ID of the factor to challenge.
  ///   - channel: How to send the code to a phone factor. The server default is
  ///     ``MessagingChannel/sms``. Ignored for other factor types.
  /// - Returns: The challenge. Pass its ``MFAChallenge/id`` to
  ///   ``verify(factorID:challengeID:code:)`` before ``MFAChallenge/expiresAt``.
  public func challenge(
    factorID: UUID,
    channel: MessagingChannel? = nil
  ) async throws -> MFAChallenge {
    try await api.authorizedExecute {
      try authAPI.challengeFactor(
        factorID: factorID, channel: channel, webAuthn: nil, accessToken: $0)
    }
  }

  /// Creates a challenge for a WebAuthn factor with relying-party options.
  ///
  /// - Parameters:
  ///   - factorID: The ID of the WebAuthn factor to challenge.
  ///   - webAuthn: The relying-party identifier and origins to challenge with.
  /// - Returns: The challenge, with the credential options in ``MFAChallenge/webauthn``.
  @_spi(Experimental)
  public func challenge(
    factorID: UUID,
    webAuthn: WebAuthnChallengeOptions
  ) async throws -> MFAChallenge {
    try await api.authorizedExecute {
      try authAPI.challengeFactor(
        factorID: factorID, channel: nil, webAuthn: webAuthn, accessToken: $0)
    }
  }

  /// Verifies a challenge with the code the user entered, and upgrades the session to `aal2`.
  ///
  /// On success the stored session is replaced with the upgraded one, the user's other sessions
  /// are signed out, and ``AuthEvent/mfaChallengeVerified`` is emitted. Verifying an `unverified`
  /// factor also marks it `verified`.
  ///
  /// - Parameters:
  ///   - factorID: The ID of the factor the challenge is for.
  ///   - challengeID: The ID returned by ``challenge(factorID:channel:)``.
  ///   - code: The code from the authenticator app or the message sent to the phone.
  /// - Returns: The upgraded session.
  /// - Throws: An error with code ``ErrorCode/mfaVerificationFailed`` when the code is wrong, or
  ///   ``ErrorCode/mfaChallengeExpired`` when the challenge has expired.
  @discardableResult
  public func verify(factorID: UUID, challengeID: UUID, code: String) async throws -> Session {
    try await commitVerifiedSession {
      try authAPI.verifyFactor(
        factorID: factorID, challengeID: challengeID, code: code, accessToken: $0)
    }
  }

  /// Verifies a WebAuthn challenge with the credential response from the authenticator, and
  /// upgrades the session to `aal2`. See ``verify(factorID:challengeID:code:)``.
  ///
  /// - Parameters:
  ///   - factorID: The ID of the WebAuthn factor the challenge is for.
  ///   - challengeID: The ID returned by ``challenge(factorID:webAuthn:)``.
  ///   - credentialResponse: The W3C credential the authenticator produced. It is sent verbatim,
  ///     with its W3C field names.
  /// - Returns: The upgraded session.
  @_spi(Experimental)
  @discardableResult
  public func verify(
    factorID: UUID,
    challengeID: UUID,
    credentialResponse: JSONValue
  ) async throws -> Session {
    try await commitVerifiedSession {
      try authAPI.verifyFactor(
        factorID: factorID, challengeID: challengeID, credentialResponse: credentialResponse,
        accessToken: $0)
    }
  }

  private func commitVerifiedSession(
    _ makeRequest: (_ accessToken: String) throws -> AuthRequest<Session>
  ) async throws -> Session {
    let session = try await api.authorizedExecute(makeRequest)
    try await sessionStore.commit(.signedIn(session, event: .mfaChallengeVerified))
    return session
  }

  /// Creates a challenge and verifies it with `code` right away.
  ///
  /// Use it for TOTP factors, where the user already has the code. For a phone factor, call
  /// ``challenge(factorID:channel:)`` first so the server sends the code.
  ///
  /// - Parameters:
  ///   - factorID: The ID of the factor to verify.
  ///   - code: The code from the authenticator app.
  /// - Returns: The upgraded session. See ``verify(factorID:challengeID:code:)``.
  @discardableResult
  public func challengeAndVerify(factorID: UUID, code: String) async throws -> Session {
    let challenge = try await challenge(factorID: factorID)
    return try await verify(factorID: factorID, challengeID: challenge.id, code: code)
  }

  /// Removes a factor.
  ///
  /// The session has to be at `aal2` to remove a `verified` factor.
  ///
  /// - Parameter factorID: The ID of the factor to remove.
  public func unenroll(factorID: UUID) async throws {
    _ = try await api.authorizedExecute {
      authAPI.unenrollFactor(factorID: factorID, accessToken: $0)
    }
  }

  /// Fetches the user's factors from the server.
  ///
  /// Reads the factors from `GET /user` on every call, so the result reflects enrollments made on
  /// other devices. The stored session is not changed.
  ///
  /// - Returns: The user's factors, split by status.
  public func factors() async throws -> MFAFactors {
    let user = try await api.authorizedExecute { authAPI.user(accessToken: $0) }
    return MFAFactors(user.factors ?? [])
  }

  /// Returns the assurance level of the current session and the highest level the user can
  /// reach.
  ///
  /// Reads the `aal` and `amr` claims of the current access token, and the factors of the stored
  /// user. It sends a request only when the session has to be refreshed.
  ///
  /// - Returns: The current level, the next level, and the methods attached to the session.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/sessionMissing`` when no user is
  ///   signed in, and of kind ``AuthError/Kind-swift.struct/decoding`` when the access token is
  ///   not a JWT.
  public func assuranceLevel() async throws -> AssuranceLevelInfo {
    let session = try await sessionManager.session()
    guard let payload = JWT.decodePayload(session.accessToken) else {
      throw AuthError.decoding("The access token is not a JWT.")
    }

    let currentLevel = (payload["aal"] as? String).map(AuthenticatorAssuranceLevel.init(rawValue:))

    let hasVerifiedFactor = session.user.factors?.contains { $0.status == .verified } ?? false
    let nextLevel = hasVerifiedFactor ? .aal2 : currentLevel

    let issuedAt = payload["iat"] as? TimeInterval
    let methods = (payload["amr"] as? [Any] ?? []).compactMap {
      AMREntry(value: $0, issuedAt: issuedAt)
    }

    return AssuranceLevelInfo(
      currentLevel: currentLevel,
      nextLevel: nextLevel,
      currentAuthenticationMethods: methods
    )
  }
}
