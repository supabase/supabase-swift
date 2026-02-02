//
//  Biometrics.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import Foundation

  /// Executes the given operation after successful biometric authentication.
  ///
  /// If biometrics are enabled and authentication is required based on the current policy,
  /// prompts the user for biometric authentication before executing the operation.
  ///
  /// - Parameters:
  ///   - clientID: The auth client ID for accessing dependencies.
  ///   - operation: The operation to execute after authentication.
  /// - Returns: The result of the operation.
  /// - Throws: ``BiometricError`` if authentication fails, or any error from the operation.
  func withBiometrics<T: Sendable>(
    clientID: AuthClientID,
    operation: @Sendable () async throws -> T
  ) async throws -> T {
    let biometricStorage = Dependencies[clientID].biometricStorage
    let biometricSession = Dependencies[clientID].biometricSession

    if biometricStorage.isEnabled,
      let policy = biometricStorage.policy,
      biometricSession.isAuthenticationRequired(policy)
    {
      let authenticator = Dependencies[clientID].biometricAuthenticator
      let title = biometricStorage.promptTitle ?? "Authenticate to continue"
      let evaluationPolicy =
        biometricStorage.evaluationPolicy ?? .deviceOwnerAuthenticationWithBiometrics

      try await authenticator.authenticate(title, evaluationPolicy)
      biometricSession.recordAuthentication()
    }

    return try await operation()
  }
#endif
