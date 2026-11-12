public import Foundation
import HTTPTypes

/// Contains the full multi-factor authentication API.
///
/// Access this namespace via ``AuthClient/mfa``.
///
/// ## Topics
///
/// ### Enrolling factors
/// - ``enroll(params:)``
/// - ``unenroll(params:)``
///
/// ### Verifying factors
/// - ``challenge(params:)``
/// - ``verify(params:)``
/// - ``challengeAndVerify(params:)``
///
/// ### Listing factors
/// - ``listFactors()``
/// - ``getAuthenticatorAssuranceLevel()``
public struct AuthMFA: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }
  var decoder: JSONDecoder { Dependencies[clientID].resolvedDecoder }
  var sessionManager: SessionManager { Dependencies[clientID].sessionManager }
  var eventEmitter: AuthStateChangeEventEmitter { Dependencies[clientID].eventEmitter }

  /// Starts the enrollment process for a new Multi-Factor Authentication (MFA) factor. This method
  /// creates a new `unverified` factor.
  /// To verify a factor, present the QR code or secret to the user and ask them to add it to their
  /// authenticator app.
  /// The user has to enter the code from their authenticator app to verify it.
  ///
  /// Upon verifying a factor, all other sessions are logged out and the current session's
  /// authenticator level is promoted to `aal2`.
  ///
  /// - Parameter params: The parameters for enrolling a new MFA factor.
  /// - Returns: An authentication response after enrolling the factor.
  @available(
    *, deprecated,
    message: "Use enrollTOTP(issuer:friendlyName:) or enrollPhone(_:friendlyName:) instead."
  )
  public func enroll(params: any MFAEnrollParamsType) async throws -> AuthMFAEnrollResponse {
    try await _enroll(params: params)
  }

  func _enroll(params: any MFAEnrollParamsType) async throws -> AuthMFAEnrollResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors"),
        method: .post,
        body: encoder.encode(params)
      )
    )
    .decoded(decoder: decoder)
  }

  /// Prepares a challenge used to verify that a user has access to a MFA factor.
  ///
  /// - Parameter params: The parameters for creating a challenge.
  /// - Returns: An authentication response with the challenge information.
  @available(*, deprecated, message: "Use challenge(factorID:channel:) instead.")
  public func challenge(params: MFAChallengeParams) async throws -> AuthMFAChallengeResponse {
    try await _challenge(params: params)
  }

  func _challenge(params: MFAChallengeParams) async throws -> AuthMFAChallengeResponse {
    let body: Data?
    if let webAuthn = params.webAuthn {
      body = try encoder.encode(["webauthn": webAuthn])
    } else if params.channel != nil {
      body = try encoder.encode(["channel": params.channel])
    } else {
      body = nil
    }

    return try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(params.factorId)/challenge"),
        method: .post,
        body: body
      )
    )
    .decoded(decoder: decoder)
  }

  /// Verifies a code against a challenge. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for verifying the MFA factor.
  /// - Returns: An authentication response after verifying the factor.
  @discardableResult
  @available(*, deprecated, message: "Use verify(factorID:challengeID:code:) instead.")
  public func verify(params: MFAVerifyParams) async throws -> AuthMFAVerifyResponse {
    try await _verify(params: params)
  }

  @discardableResult
  func _verify(params: MFAVerifyParams) async throws -> Session {
    let body: Data
    if let credentialResponse = params.credentialResponse {
      // WebAuthn credential responses use W3C camelCase field names (e.g. `clientDataJSON`).
      // Encode without the snake_case strategy so they reach the backend verbatim.
      body = try encodeWebAuthnBody([
        "factor_id": .string(params.factorId),
        "challenge_id": .string(params.challengeId),
        "webauthn": ["credential_response": credentialResponse],
      ])
    } else {
      body = try encoder.encode(params)
    }

    let response: Session = try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(params.factorId)/verify"),
        method: .post,
        body: body
      )
    ).decoded(decoder: decoder)

    await sessionManager.update(response)

    eventEmitter.emit(.mfaChallengeVerified, session: response, token: nil)

    return response
  }

  /// Unenroll removes a MFA factor.
  /// A user has to have an `aal2` authenticator level in order to unenroll a `verified` factor.
  ///
  /// - Parameter params: The parameters for unenrolling an MFA factor.
  /// - Returns: An authentication response after unenrolling the factor.
  @discardableResult
  @available(*, deprecated, message: "Use unenroll(factorID:) instead.")
  public func unenroll(params: MFAUnenrollParams) async throws -> AuthMFAUnenrollResponse {
    try await _unenroll(factorId: params.factorId)
  }

  private func _unenroll(factorId: String) async throws -> AuthMFAUnenrollResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(factorId)"),
        method: .delete
      )
    )
    .decoded(decoder: decoder)
  }

  /// Helper method which creates a challenge and immediately uses the given code to verify against
  /// it thereafter. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for creating and verifying a challenge.
  /// - Returns: An authentication response after verifying the challenge.
  @discardableResult
  @available(*, deprecated, message: "Use challengeAndVerify(factorID:code:) instead.")
  public func challengeAndVerify(
    params: MFAChallengeAndVerifyParams
  ) async throws -> AuthMFAVerifyResponse {
    let response = try await _challenge(params: MFAChallengeParams(factorId: params.factorId))
    return try await _verify(
      params: MFAVerifyParams(
        factorId: params.factorId, challengeId: response.id, code: params.code
      )
    )
  }

  /// Returns the list of MFA factors enabled for this user.
  ///
  /// - Returns: An authentication response with the list of MFA factors.
  @available(*, deprecated, message: "Use factors() instead.")
  public func listFactors() async throws -> AuthMFAListFactorsResponse {
    let user = try await sessionManager.session().user
    let factors = user.factors ?? []
    let totp = factors.filter {
      $0.factorType == "totp" && $0.status == .verified
    }
    let phone = factors.filter {
      $0.factorType == "phone" && $0.status == .verified
    }
    let webauthn = factors.filter {
      $0.factorType == "webauthn" && $0.status == .verified
    }
    return AuthMFAListFactorsResponse(all: factors, totp: totp, phone: phone, webauthn: webauthn)
  }

  /// Returns the Authenticator Assurance Level (AAL) for the active session.
  ///
  /// - Returns: An authentication response with the Authenticator Assurance Level.
  @available(*, deprecated, message: "Use assuranceLevel() instead.")
  public func getAuthenticatorAssuranceLevel() async throws
    -> AuthMFAGetAuthenticatorAssuranceLevelResponse
  {
    do {
      let session = try await sessionManager.session()
      let payload = JWT.decodePayload(session.accessToken)

      var currentLevel: String?

      if let aal = payload?["aal"] as? String {
        currentLevel = aal
      }

      var nextLevel = currentLevel

      let verifiedFactors = session.user.factors?.filter { $0.status == .verified } ?? []
      if !verifiedFactors.isEmpty {
        nextLevel = "aal2"
      }

      var currentAuthenticationMethods: [AMREntry] = []

      if let amr = payload?["amr"] as? [Any] {
        currentAuthenticationMethods = amr.compactMap(AMREntry.init(value:))
      }

      return AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: currentLevel,
        nextLevel: nextLevel,
        currentAuthenticationMethods: currentAuthenticationMethods
      )
    } catch AuthError.sessionMissing {
      return AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: nil,
        nextLevel: nil,
        currentAuthenticationMethods: []
      )
    }
  }
}

// MARK: - Direct-argument methods

extension AuthMFA {
  /// Starts the enrollment of a time-based one-time password (TOTP) factor.
  ///
  /// Show the returned QR code or secret to the user, then verify a code from their
  /// authenticator app with ``challengeAndVerify(factorID:code:)``. The factor stays `unverified`
  /// until then.
  ///
  /// - Parameters:
  ///   - issuer: The domain the user is enrolling with.
  ///   - friendlyName: A name that tells this factor apart from the user's other factors.
  /// - Returns: The new factor, with the QR code, the secret, and the `otpauth://` URI.
  public func enrollTOTP(
    issuer: String? = nil,
    friendlyName: String? = nil
  ) async throws -> TOTPEnrollment {
    try await enroll(
      FactorEnrollmentBody(factorType: "totp", friendlyName: friendlyName, issuer: issuer))
  }

  /// Starts the enrollment of a phone factor.
  ///
  /// Send a code with ``challenge(factorID:channel:)``, then verify it with
  /// ``verify(factorID:challengeID:code:)``. The factor stays `unverified` until then.
  ///
  /// - Parameters:
  ///   - phone: The phone number, in E.164 format.
  ///   - friendlyName: A name that tells this factor apart from the user's other factors.
  /// - Returns: The new factor.
  public func enrollPhone(
    _ phone: String,
    friendlyName: String? = nil
  ) async throws -> PhoneEnrollment {
    try await enroll(
      FactorEnrollmentBody(factorType: "phone", friendlyName: friendlyName, phone: phone))
  }

  /// Creates a challenge for a factor. For a phone factor, this sends the code.
  ///
  /// - Parameters:
  ///   - factorID: ID of the factor to challenge. A ``Factor/id`` is a `String` in this version;
  ///     convert it with `UUID(uuidString:)`.
  ///   - channel: The channel that carries the code of a phone factor.
  /// - Returns: The challenge. Pass its ID to ``verify(factorID:challengeID:code:)``.
  public func challenge(
    factorID: UUID,
    channel: MessagingChannel? = nil
  ) async throws -> MFAChallenge {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(factorID.wireID)/challenge"),
        method: .post,
        body: channel == nil ? nil : try encoder.encode(["channel": channel])
      )
    )
    .decoded(decoder: decoder)
  }

  /// Verifies a code against a challenge.
  ///
  /// On success the stored session is replaced, and the client emits
  /// ``AuthChangeEvent/mfaChallengeVerified``.
  ///
  /// - Parameters:
  ///   - factorID: ID of the factor being verified.
  ///   - challengeID: ID of the challenge from ``challenge(factorID:channel:)``.
  ///   - code: The code from the user's authenticator app or phone.
  /// - Returns: The new session.
  @discardableResult
  public func verify(factorID: UUID, challengeID: UUID, code: String) async throws -> Session {
    try await _verify(
      params: MFAVerifyParams(
        factorId: factorID.wireID, challengeId: challengeID.wireID, code: code))
  }

  /// Creates a challenge for a factor and verifies a code against it. Use it for TOTP factors,
  /// where the code is available without a challenge.
  ///
  /// - Parameters:
  ///   - factorID: ID of the factor to verify.
  ///   - code: The code from the user's authenticator app.
  /// - Returns: The new session.
  @discardableResult
  public func challengeAndVerify(factorID: UUID, code: String) async throws -> Session {
    let challenge = try await challenge(factorID: factorID)
    return try await verify(factorID: factorID, challengeID: challenge.id, code: code)
  }

  /// Removes a factor from the user.
  ///
  /// - Parameter factorID: ID of the factor to remove.
  /// - Returns: The ID of the removed factor.
  @discardableResult
  public func unenroll(factorID: UUID) async throws -> AuthMFAUnenrollResponse {
    try await _unenroll(factorId: factorID.wireID)
  }

  /// Returns the user's MFA factors, split by status.
  ///
  /// In this version the factors come from the stored session, with no request. Refresh the
  /// session first when another device may have changed them.
  ///
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored.
  public func factors() async throws -> MFAFactors {
    MFAFactors(try await sessionManager.session().user.factors ?? [])
  }

  /// Returns the assurance level of the current session and the highest level the user can
  /// reach.
  ///
  /// Reads the `aal` and `amr` claims of the current access token, and the factors of the stored
  /// session.
  ///
  /// - Returns: The current level, the next level, and the methods attached to the session.
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored.
  public func assuranceLevel() async throws -> AssuranceLevelInfo {
    let session = try await sessionManager.session()
    let payload = JWT.decodePayload(session.accessToken)

    let currentLevel = (payload?["aal"] as? String).map(AuthenticatorAssuranceLevel.init(rawValue:))
    let hasVerifiedFactor = session.user.factors?.contains { $0.status == .verified } ?? false

    return AssuranceLevelInfo(
      currentLevel: currentLevel,
      nextLevel: hasVerifiedFactor ? .aal2 : currentLevel,
      currentAuthenticationMethods: (payload?["amr"] as? [Any] ?? []).compactMap(
        AMREntry.init(value:))
    )
  }

  private func enroll<Enrollment: Decodable>(
    _ body: FactorEnrollmentBody
  ) async throws -> Enrollment {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors"),
        method: .post,
        body: encoder.encode(body)
      )
    )
    .decoded(decoder: decoder)
  }
}

private struct FactorEnrollmentBody: Encodable {
  var factorType: String
  var friendlyName: String?
  var issuer: String?
  var phone: String?
}

extension UUID {
  /// The lowercase form the Auth server uses for IDs.
  fileprivate var wireID: String { uuidString.lowercased() }
}
