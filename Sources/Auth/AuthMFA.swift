import _Helpers
import Foundation

/// Contains the full multi-factor authentication API.
public struct AuthMFA: Sendable {
  var configuration: AuthClient.Configuration { Current.configuration }
  var api: APIClient { Current.api }
  var encoder: JSONEncoder { Current.encoder }
  var decoder: JSONDecoder { Current.decoder }
  var sessionManager: SessionManager { Current.sessionManager }
  var eventEmitter: AuthStateChangeEventEmitter { Current.eventEmitter }

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
  public func enroll(params: MFAEnrollParams) async throws -> AuthMFAEnrollResponse {
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
  public func challenge(params: MFAChallengeParams) async throws -> AuthMFAChallengeResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(params.factorId)/challenge"),
        method: .post
      )
    )
    .decoded(decoder: decoder)
  }

  /// Verifies a code against a challenge. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for verifying the MFA factor.
  /// - Returns: An authentication response after verifying the factor.
  public func verify(params: MFAVerifyParams) async throws -> AuthMFAVerifyResponse {
    let response: AuthMFAVerifyResponse = try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(params.factorId)/verify"),
        method: .post,
        body: encoder.encode(params)
      )
    ).decoded(decoder: decoder)

    try await sessionManager.update(response)

    eventEmitter.emit(.mfaChallengeVerified, session: response, token: nil)

    return response
  }

  /// Unenroll removes a MFA factor.
  /// A user has to have an `aal2` authenticator level in order to unenroll a `verified` factor.
  ///
  /// - Parameter params: The parameters for unenrolling an MFA factor.
  /// - Returns: An authentication response after unenrolling the factor.
  @discardableResult
  public func unenroll(params: MFAUnenrollParams) async throws -> AuthMFAUnenrollResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("factors/\(params.factorId)"),
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
  public func challengeAndVerify(
    params: MFAChallengeAndVerifyParams
  ) async throws -> AuthMFAVerifyResponse {
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
  public func listFactors() async throws -> AuthMFAListFactorsResponse {
    let user = try await sessionManager.session().user
    let factors = user.factors ?? []
    let totp = factors.filter {
      $0.factorType == "totp" && $0.status == .verified
    }
    return AuthMFAListFactorsResponse(all: factors, totp: totp)
  }

  /// Returns the Authenticator Assurance Level (AAL) for the active session.
  ///
  /// - Returns: An authentication response with the Authenticator Assurance Level.
  public func getAuthenticatorAssuranceLevel() async throws
    -> AuthMFAGetAuthenticatorAssuranceLevelResponse
  {
    do {
      let session = try await sessionManager.session()
      let payload = try decode(jwt: session.accessToken)

      var currentLevel: AuthenticatorAssuranceLevels?

      if let aal = payload["aal"] as? AuthenticatorAssuranceLevels {
        currentLevel = aal
      }

      var nextLevel = currentLevel

      let verifiedFactors = session.user.factors?.filter { $0.status == .verified } ?? []
      if !verifiedFactors.isEmpty {
        nextLevel = "aal2"
      }

      var currentAuthenticationMethods: [AMREntry] = []

      if let amr = payload["amr"] as? [Any] {
        currentAuthenticationMethods = amr.compactMap(AMREntry.init(value:))
      }

      return AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: currentLevel,
        nextLevel: nextLevel,
        currentAuthenticationMethods: currentAuthenticationMethods
      )
    } catch AuthError.sessionNotFound {
      return AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: nil,
        nextLevel: nil,
        currentAuthenticationMethods: []
      )
    } catch {
      throw error
    }
  }
}
