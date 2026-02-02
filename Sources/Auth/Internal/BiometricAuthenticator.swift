//
//  BiometricAuthenticator.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import Foundation
  import LocalAuthentication

  /// Wrapper around LAContext for biometric authentication with testability.
  struct BiometricAuthenticator: Sendable {
    var checkAvailability: @Sendable () -> BiometricAvailability
    var authenticate:
      @Sendable (_ reason: String, _ policy: BiometricEvaluationPolicy) async throws
        -> Void
  }

  extension BiometricAuthenticator {
    static var live: BiometricAuthenticator {
      BiometricAuthenticator(
        checkAvailability: {
          let context = LAContext()
          var error: NSError?
          let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
          )

          if canEvaluate {
            return BiometricAvailability(
              isAvailable: true,
              biometryType: context.biometryType,
              error: nil
            )
          }

          let biometricError: BiometricError
          if let error = error {
            biometricError = mapLAError(error)
          } else {
            biometricError = .notAvailable(reason: .noBiometryAvailable)
          }

          return BiometricAvailability(
            isAvailable: false,
            biometryType: context.biometryType,
            error: biometricError
          )
        },
        authenticate: { reason, policy in
          let context = LAContext()

          do {
            let success = try await context.evaluatePolicy(
              policy.laPolicy,
              localizedReason: reason
            )

            guard success else {
              throw BiometricError.authenticationFailed(message: "Authentication returned false")
            }
          } catch let error as LAError {
            throw mapLAError(error as NSError)
          } catch let error as BiometricError {
            throw error
          } catch {
            throw BiometricError.authenticationFailed(message: error.localizedDescription)
          }
        }
      )
    }

    /// Creates a mock authenticator for testing.
    static func mock(
      available: Bool = true,
      biometryType: LABiometryType = .faceID,
      shouldSucceed: Bool = true,
      error: BiometricError? = nil
    ) -> BiometricAuthenticator {
      BiometricAuthenticator(
        checkAvailability: {
          BiometricAvailability(
            isAvailable: available,
            biometryType: biometryType,
            error: available ? nil : (error ?? .notAvailable(reason: .noBiometryAvailable))
          )
        },
        authenticate: { _, _ in
          if !shouldSucceed {
            throw error ?? .authenticationFailed(message: "Mock failure")
          }
        }
      )
    }
  }

  private func mapLAError(_ error: NSError) -> BiometricError {
    let laError = LAError.Code(rawValue: error.code) ?? .systemCancel

    switch laError {
    case .userCancel, .appCancel:
      return .userCancelled
    case .biometryNotAvailable:
      return .notAvailable(reason: .noBiometryAvailable)
    case .biometryNotEnrolled:
      return .notEnrolled
    case .biometryLockout:
      return .lockedOut
    case .passcodeNotSet:
      return .notAvailable(reason: .passcodeNotSet)
    case .authenticationFailed:
      return .authenticationFailed(message: "Biometric authentication failed")
    default:
      return .authenticationFailed(message: error.localizedDescription)
    }
  }
#endif
