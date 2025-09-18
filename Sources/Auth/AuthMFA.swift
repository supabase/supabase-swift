import Foundation

/// Multi-factor authentication API for Supabase Auth.
///
/// The `AuthMFA` struct provides comprehensive multi-factor authentication functionality
/// including enrolling factors, challenging users, and verifying MFA codes. It supports
/// TOTP (Time-based One-Time Password) factors for authenticator apps.
///
/// ## Basic Usage
///
/// ```swift
/// // Enroll a new MFA factor
/// let enrollment = try await authClient.mfa.enroll(
///   params: MFAEnrollParams(
///     factorType: .totp,
///     friendlyName: "My Authenticator App"
///   )
/// )
///
/// // Challenge the user with the factor
/// let challenge = try await authClient.mfa.challenge(
///   params: MFAChallengeParams(factorId: enrollment.id)
/// )
///
/// // Verify the MFA code
/// let verification = try await authClient.mfa.verify(
///   params: MFAVerifyParams(
///     factorId: enrollment.id,
///     code: "123456"
///   )
/// )
/// ```
///
/// ## Complete MFA Flow
///
/// ```swift
/// // 1. Enroll factor
/// let enrollment = try await authClient.mfa.enroll(
///   params: MFAEnrollParams(
///     factorType: .totp,
///     friendlyName: "My Phone"
///   )
/// )
///
/// // 2. Show QR code to user (enrollment.totp.qrCode)
/// // User scans QR code with authenticator app
///
/// // 3. Challenge the factor
/// let challenge = try await authClient.mfa.challenge(
///   params: MFAChallengeParams(factorId: enrollment.id)
/// )
///
/// // 4. User enters code from authenticator app
/// let verification = try await authClient.mfa.verify(
///   params: MFAVerifyParams(
///     factorId: enrollment.id,
///     code: userEnteredCode
///   )
/// )
///
/// // 5. MFA is now enabled for the user
/// ```
public struct AuthMFA: Sendable {
  let client: AuthClient

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
  public func enroll(params: any MFAEnrollParamsType) async throws(AuthError)
    -> AuthMFAEnrollResponse
  {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("factors"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await self.client.sessionManager.session().accessToken)
        ],
        body: params
      )
      .serializingDecodable(AuthMFAEnrollResponse.self, decoder: self.client.configuration.decoder)
      .value
    }
  }

  /// Prepares a challenge used to verify that a user has access to a MFA factor.
  ///
  /// - Parameter params: The parameters for creating a challenge.
  /// - Returns: An authentication response with the challenge information.
  public func challenge(params: MFAChallengeParams) async throws(AuthError)
    -> AuthMFAChallengeResponse
  {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("factors/\(params.factorId)/challenge"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await self.client.sessionManager.session().accessToken)
        ],
        body: params.channel == nil ? nil : ["channel": params.channel]
      )
      .serializingDecodable(
        AuthMFAChallengeResponse.self, decoder: self.client.configuration.decoder
      )
      .value
    }
  }

  /// Verifies a code against a challenge. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for verifying the MFA factor.
  /// - Returns: An authentication response after verifying the factor.
  @discardableResult
  public func verify(params: MFAVerifyParams) async throws(AuthError) -> AuthMFAVerifyResponse {
    return try await wrappingError(or: mapToAuthError) {
      let response = try await self.client.execute(
        self.client.url.appendingPathComponent("factors/\(params.factorId)/verify"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await self.client.sessionManager.session().accessToken)
        ],
        body: params
      )
      .serializingDecodable(AuthMFAVerifyResponse.self, decoder: self.client.configuration.decoder)
      .value

      await self.client.sessionManager.update(response)

      self.client.eventEmitter.emit(.mfaChallengeVerified, session: response, token: nil)

      return response
    }
  }

  /// Unenroll removes a MFA factor.
  /// A user has to have an `aal2` authenticator level in order to unenroll a `verified` factor.
  ///
  /// - Parameter params: The parameters for unenrolling an MFA factor.
  /// - Returns: An authentication response after unenrolling the factor.
  @discardableResult
  public func unenroll(params: MFAUnenrollParams) async throws(AuthError) -> AuthMFAUnenrollResponse
  {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("factors/\(params.factorId)"),
        method: .delete,
        headers: [
          .authorization(bearerToken: try await self.client.sessionManager.session().accessToken)
        ]
      )
      .serializingDecodable(
        AuthMFAUnenrollResponse.self, decoder: self.client.configuration.decoder
      )
      .value
    }
  }

  /// Helper method which creates a challenge and immediately uses the given code to verify against
  /// it thereafter. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for creating and verifying a challenge.
  /// - Returns: An authentication response after verifying the challenge.
  @discardableResult
  public func challengeAndVerify(
    params: MFAChallengeAndVerifyParams
  ) async throws(AuthError) -> AuthMFAVerifyResponse {
    let response = try await challenge(params: MFAChallengeParams(factorId: params.factorId))
    return try await verify(
      params: MFAVerifyParams(
        factorId: params.factorId, challengeId: response.id, code: params.code
      )
    )
  }

  /// Returns the list of MFA factors enabled for this user.
  ///
  /// - Returns: An authentication response with the list of MFA factors.
  public func listFactors() async throws(AuthError) -> AuthMFAListFactorsResponse {
    try await wrappingError(or: mapToAuthError) {
      let user = try await self.client.sessionManager.session().user
      let factors = user.factors ?? []
      let totp = factors.filter {
        $0.factorType == "totp" && $0.status == .verified
      }
      let phone = factors.filter {
        $0.factorType == "phone" && $0.status == .verified
      }
      return AuthMFAListFactorsResponse(all: factors, totp: totp, phone: phone)
    }
  }

  /// Returns the Authenticator Assurance Level (AAL) for the active session.
  ///
  /// - Returns: An authentication response with the Authenticator Assurance Level.
  public func getAuthenticatorAssuranceLevel() async throws(AuthError)
    -> AuthMFAGetAuthenticatorAssuranceLevelResponse
  {
    do {
      return try await wrappingError(or: mapToAuthError) {
        let session = try await self.client.sessionManager.session()
        let payload = JWT.decodePayload(session.accessToken)

        var currentLevel: AuthenticatorAssuranceLevels?

        if let aal = payload?["aal"] as? AuthenticatorAssuranceLevels {
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
      }
    } catch AuthError.sessionMissing {
      return AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: nil,
        nextLevel: nil,
        currentAuthenticationMethods: []
      )
    }
  }

}
