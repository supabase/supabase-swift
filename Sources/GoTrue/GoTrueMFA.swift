//
//  File.swift
//
//
//  Created by Guilherme Souza on 26/10/23.
//

import Foundation

/// Contains the full multi-factor authentication API.
public actor GoTrueMFA {
  /// Starts the enrollment process for a new Multi-Factor Authentication (MFA)
  /// factor. This method creates a new `unverified` factor.
  /// To verify a factor, present the QR code or secret to the user and ask them to add it to their
  /// authenticator app.
  /// The user has to enter the code from their authenticator app to verify it.
  ///
  /// Upon verifying a factor, all other sessions are logged out and the current session's authenticator level is promoted to `aal2`.
  ///
  /// - Parameter params: The parameters for enrolling a new MFA factor.
  /// - Returns: An authentication response after enrolling the factor.
  public func enroll(params: MFAEnrollParams) async throws -> AuthMFAEnrollResponse {
    fatalError()
  }

  /// Prepares a challenge used to verify that a user has access to a MFA factor.
  ///
  /// - Parameter params: The parameters for creating a challenge.
  /// - Returns: An authentication response with the challenge information.
  public func challenge(params: MFAChallengeParams) async throws -> AuthMFAChallengeResponse {
    fatalError()
  }

  /// Verifies a code against a challenge. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for verifying the MFA factor.
  /// - Returns: An authentication response after verifying the factor.
  public func verify(params: MFAVerifyParams) async throws -> AuthMFAVerifyResponse {
    fatalError()
  }

  /// Unenroll removes a MFA factor.
  /// A user has to have an `aal2` authenticator level in order to unenroll a `verified` factor.
  ///
  /// - Parameter params: The parameters for unenrolling an MFA factor.
  /// - Returns: An authentication response after unenrolling the factor.
  public func unenroll(params: MFAUnenrollParams) async throws -> AuthMFAUnenrollResponse {
    fatalError()
  }

  /// Helper method which creates a challenge and immediately uses the given code to verify against it thereafter. The verification code is
  /// provided by the user by entering a code seen in their authenticator app.
  ///
  /// - Parameter params: The parameters for creating and verifying a challenge.
  /// - Returns: An authentication response after verifying the challenge.
  public func challengeAndVerify(params: MFAChallengeAndVerifyParams) async throws
    -> AuthMFAVerifyResponse
  {
    fatalError()
  }

  /// Returns the list of MFA factors enabled for this user.
  ///
  /// - Returns: An authentication response with the list of MFA factors.
  public func listFactors() async throws -> AuthMFAListFactorsResponse {
    fatalError()
  }

  /// Returns the Authenticator Assurance Level (AAL) for the active session.
  ///
  /// - Returns: An authentication response with the Authenticator Assurance Level.
  public func getAuthenticatorAssuranceLevel() async throws
    -> AuthMFAGetAuthenticatorAssuranceLevelResponse
  {
    fatalError()
  }
}
