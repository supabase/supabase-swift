// MARK: - Biometrics

#if canImport(LocalAuthentication)
  import LocalAuthentication

  extension AuthClient {
    /// Check if biometrics are available on this device.
    ///
    /// Returns information about the device's biometric capabilities including
    /// the type of biometry available (Face ID, Touch ID, or Optic ID) and any
    /// errors preventing biometric authentication.
    ///
    /// - Returns: A ``BiometricAvailability`` instance describing the device's biometric capabilities.
    nonisolated public func biometricsAvailability() -> BiometricAvailability {
      Dependencies[clientID].biometricAuthenticator.checkAvailability()
    }

    /// Whether biometrics are currently enabled for session protection.
    ///
    /// When biometrics are enabled, accessing the ``session`` property will
    /// require biometric authentication based on the configured policy.
    nonisolated public var isBiometricsEnabled: Bool {
      Dependencies[clientID].biometricStorage.isEnabled
    }

    /// Enable biometric protection for session retrieval.
    ///
    /// After enabling, calls to ``session`` will require biometric authentication
    /// based on the configured policy. The user will be prompted for biometric
    /// authentication immediately to verify that biometrics are working.
    ///
    /// - Parameters:
    ///   - title: The message displayed to the user during the biometric prompt.
    ///   - evaluationPolicy: The evaluation policy to use for authentication.
    ///   - policy: The biometric policy determining when authentication is required.
    ///
    /// - Throws: ``BiometricError`` if biometrics are not available or authentication fails.
    public func enableBiometrics(
      title: String = "Authenticate to access your account",
      evaluationPolicy: BiometricEvaluationPolicy = .deviceOwnerAuthenticationWithBiometrics,
      policy: BiometricPolicy = .default
    ) async throws {
      let availability = biometricsAvailability()
      guard availability.isAvailable else {
        throw availability.error ?? BiometricError.notAvailable(reason: .noBiometryAvailable)
      }

      // Verify biometrics work before enabling
      try await Dependencies[clientID].biometricAuthenticator.authenticate(title, evaluationPolicy)

      // Store biometric settings
      Dependencies[clientID].biometricStorage.enable(evaluationPolicy, policy, title)

      // Update session timestamp
      Dependencies[clientID].biometricSession.recordAuthentication()
    }

    /// Disable biometric protection for session retrieval.
    ///
    /// After disabling, sessions can be retrieved without biometric authentication.
    nonisolated public func disableBiometrics() {
      Dependencies[clientID].biometricStorage.disable()
      Dependencies[clientID].biometricSession.reset()
    }

    /// Check if biometric authentication would be required on next session access.
    ///
    /// This is useful for UI purposes, for example to show a lock icon or
    /// prepare the user for a biometric prompt.
    ///
    /// - Returns: `true` if biometric authentication would be required to access the session.
    nonisolated public func isBiometricAuthenticationRequired() -> Bool {
      guard isBiometricsEnabled,
        let policy = Dependencies[clientID].biometricStorage.policy
      else {
        return false
      }
      return Dependencies[clientID].biometricSession.isAuthenticationRequired(policy)
    }

    /// Invalidate the biometric session, forcing re-authentication on next access.
    ///
    /// Use this when you want to ensure the user must re-authenticate with biometrics
    /// on the next session access, for example when the app enters a sensitive area
    /// or after a period of inactivity.
    nonisolated public func invalidateBiometricSession() {
      Dependencies[clientID].biometricSession.reset()
    }
  }
#endif
