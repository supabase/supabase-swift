import Foundation

/// Contains the full multi-factor authentication API.
public struct AuthMFA: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].encoder }
  var decoder: JSONDecoder { Dependencies[clientID].decoder }
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
  public func enroll(params: any MFAEnrollParamsType) async throws(AuthError)
    -> AuthMFAEnrollResponse
  {
    try await wrappingError(or: mapToAuthError) {
      try await self.api.execute(
        self.configuration.url.appendingPathComponent("factors"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await sessionManager.session().accessToken)
        ],
        body: params
      )
      .serializingDecodable(AuthMFAEnrollResponse.self, decoder: configuration.decoder)
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
      try await self.api.execute(
        self.configuration.url.appendingPathComponent("factors/\(params.factorId)/challenge"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await sessionManager.session().accessToken)
        ],
        body: params.channel == nil ? nil : ["channel": params.channel]
      )
      .serializingDecodable(AuthMFAChallengeResponse.self, decoder: configuration.decoder)
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
      let response = try await self.api.execute(
        self.configuration.url.appendingPathComponent("factors/\(params.factorId)/verify"),
        method: .post,
        headers: [
          .authorization(bearerToken: try await sessionManager.session().accessToken)
        ],
        body: params
      )
      .serializingDecodable(AuthMFAVerifyResponse.self, decoder: configuration.decoder)
      .value

      await sessionManager.update(response)

      eventEmitter.emit(.mfaChallengeVerified, session: response, token: nil)

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
      try await self.api.execute(
        self.configuration.url.appendingPathComponent("factors/\(params.factorId)"),
        method: .delete,
        headers: [
          .authorization(bearerToken: try await sessionManager.session().accessToken)
        ]
      )
      .serializingDecodable(AuthMFAUnenrollResponse.self, decoder: configuration.decoder)
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
      let user = try await sessionManager.session().user
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
        let session = try await sessionManager.session()
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

  /// Checks if the current session has sufficient MFA factors for the required AAL level.
  ///
  /// - Parameter requiredLevel: The required Authenticator Assurance Level.
  /// - Returns: `true` if the session meets the required AAL level, `false` otherwise.
  public func hasSufficientAAL(requiredLevel: AuthenticatorAssuranceLevels) async throws(AuthError) -> Bool {
    let aalResponse = try await getAuthenticatorAssuranceLevel()
    
    switch requiredLevel {
    case "aal1":
      return aalResponse.currentLevel != nil
    case "aal2":
      return aalResponse.currentLevel == "aal2"
    default:
      return false
    }
  }

  /// Gets the count of verified MFA factors for the current user.
  ///
  /// - Returns: The number of verified MFA factors.
  public func getVerifiedFactorCount() async throws(AuthError) -> Int {
    let factors = try await listFactors()
    return factors.all.filter { $0.status == .verified }.count
  }

  /// Checks if the user has any verified MFA factors.
  ///
  /// - Returns: `true` if the user has at least one verified MFA factor, `false` otherwise.
  public func hasVerifiedFactors() async throws(AuthError) -> Bool {
    let count = try await getVerifiedFactorCount()
    return count > 0
  }

  /// Gets all verified TOTP factors for the current user.
  ///
  /// - Returns: An array of verified TOTP factors.
  public func getVerifiedTotpFactors() async throws(AuthError) -> [Factor] {
    let factors = try await listFactors()
    return factors.totp
  }

  /// Gets all verified phone factors for the current user.
  ///
  /// - Returns: An array of verified phone factors.
  public func getVerifiedPhoneFactors() async throws(AuthError) -> [Factor] {
    let factors = try await listFactors()
    return factors.phone
  }
}
