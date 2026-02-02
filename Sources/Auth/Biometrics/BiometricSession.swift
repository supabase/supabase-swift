//
//  BiometricSession.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import ConcurrencyExtras
  import Foundation

  /// Tracks biometric authentication state for session-based policies.
  struct BiometricSession: Sendable {
    var recordAuthentication: @Sendable () -> Void
    var reset: @Sendable () -> Void
    var lastAuthenticationTime: @Sendable () -> Date?
    var isAuthenticationRequired: @Sendable (_ policy: BiometricPolicy) -> Bool
  }

  extension BiometricSession {
    static func live(clientID: AuthClientID) -> BiometricSession {
      let lastAuthTime = LockIsolated<Date?>(nil)
      let isInBackground = LockIsolated(false)

      // Subscribe to app lifecycle notifications
      #if canImport(ObjectiveC)
        Task { @MainActor in
          AppLifecycle.observeBackgroundTransitions(
            onEnterBackground: {
              isInBackground.setValue(true)
            },
            onEnterForeground: {
              // Keep isInBackground true until authentication completes
            }
          )
        }
      #endif

      return BiometricSession(
        recordAuthentication: {
          lastAuthTime.setValue(Date())
          isInBackground.setValue(false)
        },
        reset: {
          lastAuthTime.setValue(nil)
        },
        lastAuthenticationTime: {
          lastAuthTime.value
        },
        isAuthenticationRequired: { policy in
          switch policy {
          case .default:
            // Required only on first access (no previous authentication)
            return lastAuthTime.value == nil

          case .always:
            return true

          case .session(let timeout):
            guard let lastAuth = lastAuthTime.value else {
              return true
            }
            return Date().timeIntervalSince(lastAuth) > timeout

          case .appLifecycle:
            return isInBackground.value || lastAuthTime.value == nil
          }
        }
      )
    }
  }
#endif
