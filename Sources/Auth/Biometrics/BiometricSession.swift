//
//  BiometricSession.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import ConcurrencyExtras
  import Foundation

  #if canImport(UIKit)
    import UIKit
  #endif

  #if canImport(AppKit)
    import AppKit
  #endif

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
      #if canImport(UIKit) && !os(watchOS)
        Task { @MainActor in
          NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
          ) { _ in
            isInBackground.setValue(true)
          }

          NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
          ) { _ in
            // Keep isInBackground true until authentication completes
          }
        }
      #elseif canImport(AppKit)
        Task { @MainActor in
          NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
          ) { _ in
            isInBackground.setValue(true)
          }
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
