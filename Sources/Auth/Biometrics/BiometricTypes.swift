//
//  BiometricTypes.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import Foundation
  import LocalAuthentication

  /// Policy determining when biometric authentication is required.
  public enum BiometricPolicy: Sendable, Hashable {
    /// Biometric authentication is required on first access only.
    /// After successful authentication, no further prompts until app terminates.
    case `default`

    /// Biometric authentication is always required before retrieving credentials.
    case always

    /// Biometric authentication is required if the specified timeout has elapsed
    /// since the last successful authentication.
    case session(timeoutInSeconds: TimeInterval)

    /// Biometric authentication is required when app returns from background.
    case appLifecycle
  }

  /// Evaluation policy for LocalAuthentication.
  public enum BiometricEvaluationPolicy: Sendable {
    /// Device owner authentication with biometrics only (Face ID / Touch ID).
    /// Falls back to nothing if biometrics unavailable.
    case deviceOwnerAuthenticationWithBiometrics

    /// Device owner authentication with biometrics or device passcode fallback.
    case deviceOwnerAuthentication

    var laPolicy: LAPolicy {
      switch self {
      case .deviceOwnerAuthenticationWithBiometrics:
        return .deviceOwnerAuthenticationWithBiometrics
      case .deviceOwnerAuthentication:
        return .deviceOwnerAuthentication
      }
    }
  }

  /// Result of biometric availability check.
  public struct BiometricAvailability: Sendable {
    /// Whether biometrics are available on the device.
    public let isAvailable: Bool

    /// The type of biometry available (Face ID, Touch ID, Optic ID, or none).
    public let biometryType: LABiometryType

    /// Error if biometrics are not available.
    public let error: BiometricError?

    public init(isAvailable: Bool, biometryType: LABiometryType, error: BiometricError?) {
      self.isAvailable = isAvailable
      self.biometryType = biometryType
      self.error = error
    }
  }

  /// Errors specific to biometric authentication operations.
  public enum BiometricError: LocalizedError, Sendable, Equatable {
    /// Biometrics are not available on this device.
    case notAvailable(reason: BiometricUnavailableReason)

    /// User cancelled the biometric authentication.
    case userCancelled

    /// Biometric authentication failed.
    case authenticationFailed(message: String)

    /// Biometrics are not enrolled on this device.
    case notEnrolled

    /// Biometric authentication was locked out due to too many failed attempts.
    case lockedOut

    public var errorDescription: String? {
      switch self {
      case .notAvailable(let reason):
        return "Biometrics not available: \(reason.localizedDescription)"
      case .userCancelled:
        return "Biometric authentication was cancelled by the user."
      case .authenticationFailed(let message):
        return "Biometric authentication failed: \(message)"
      case .notEnrolled:
        return "No biometrics enrolled on this device."
      case .lockedOut:
        return "Biometrics locked out due to too many failed attempts."
      }
    }
  }

  /// Reason why biometrics are not available.
  public enum BiometricUnavailableReason: Sendable, Equatable {
    /// No biometric hardware available on this device.
    case noBiometryAvailable

    /// Device passcode is not set.
    case passcodeNotSet

    var localizedDescription: String {
      switch self {
      case .noBiometryAvailable:
        return "No biometric hardware available."
      case .passcodeNotSet:
        return "Device passcode is not set."
      }
    }
  }
#endif
