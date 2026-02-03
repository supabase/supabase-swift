//
//  BiometricKeychainLocalStorage.swift
//  Auth
//
//  Keychain storage with biometric access control
//

#if canImport(LocalAuthentication)
  import Foundation
  import LocalAuthentication
  import Security

  /// Biometric access control options for keychain storage.
  public enum BiometricAccessControl: Sendable {
    /// Requires biometric authentication (Face ID / Touch ID).
    /// No fallback to device passcode.
    case biometryOnly

    /// Requires biometric authentication with device passcode as fallback.
    case biometryOrPasscode

    /// Requires user presence - biometrics, passcode, or Apple Watch.
    case userPresence

    var accessControlFlags: SecAccessControlCreateFlags {
      switch self {
      case .biometryOnly:
        return .biometryCurrentSet
      case .biometryOrPasscode:
        return [.biometryCurrentSet, .or, .devicePasscode]
      case .userPresence:
        return .userPresence
      }
    }
  }

  /// ``AuthLocalStorage`` implementation using Keychain with biometric access control.
  ///
  /// When biometrics are enabled, the system will automatically prompt for biometric authentication
  /// when attempting to retrieve stored data.
  ///
  /// Example usage:
  /// ```swift
  /// let client = SupabaseClient(
  ///   supabaseURL: url,
  ///   supabaseKey: key,
  ///   options: .init(
  ///     auth: .init(
  ///       localStorage: BiometricKeychainLocalStorage(
  ///         accessControl: .biometryOrPasscode,
  ///         promptMessage: "Authenticate to access your account"
  ///       )
  ///     )
  ///   )
  /// )
  /// ```
  public struct BiometricKeychainLocalStorage: AuthLocalStorage {
    private let service: String
    private let accessGroup: String?
    private let accessControl: BiometricAccessControl
    private let promptMessage: String

    /// Creates a new biometric keychain storage.
    ///
    /// - Parameters:
    ///   - service: The keychain service identifier.
    ///   - accessGroup: Optional keychain access group for sharing between apps.
    ///   - accessControl: The biometric access control level.
    ///   - promptMessage: The message shown in the biometric prompt.
    public init(
      service: String = "supabase.gotrue.swift",
      accessGroup: String? = nil,
      accessControl: BiometricAccessControl = .biometryOrPasscode,
      promptMessage: String = "Authenticate to access your session"
    ) {
      self.service = service
      self.accessGroup = accessGroup
      self.accessControl = accessControl
      self.promptMessage = promptMessage
    }

    public func store(key: String, value: Data) throws {
      // Create access control with biometric protection
      var error: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(
          kCFAllocatorDefault,
          kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
          accessControl.accessControlFlags,
          &error
        )
      else {
        if let error = error?.takeRetainedValue() {
          throw BiometricKeychainError.accessControlCreationFailed(error as Error)
        }
        throw BiometricKeychainError.accessControlCreationFailed(nil)
      }

      // Try to add the item first
      var query = baseQuery(key: key)
      query[kSecValueData as String] = value
      query[kSecAttrAccessControl as String] = access

      let addStatus = SecItemAdd(query as CFDictionary, nil)

      if addStatus == errSecDuplicateItem {
        // Item exists, delete and re-add (can't update access control)
        try remove(key: key)

        let retryStatus = SecItemAdd(query as CFDictionary, nil)
        if retryStatus != errSecSuccess {
          throw BiometricKeychainError.keychainError(status: retryStatus)
        }
      } else if addStatus != errSecSuccess {
        throw BiometricKeychainError.keychainError(status: addStatus)
      }
    }

    public func retrieve(key: String) throws -> Data? {
      var query = baseQuery(key: key)
      query[kSecReturnData as String] = kCFBooleanTrue
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      query[kSecUseOperationPrompt as String] = promptMessage

      var result: AnyObject?
      let status = SecItemCopyMatching(query as CFDictionary, &result)

      switch status {
      case errSecSuccess:
        return result as? Data
      case errSecItemNotFound:
        return nil
      case errSecUserCanceled:
        throw BiometricKeychainError.userCanceled
      case errSecAuthFailed:
        throw BiometricKeychainError.authenticationFailed
      default:
        throw BiometricKeychainError.keychainError(status: status)
      }
    }

    public func remove(key: String) throws {
      let query = baseQuery(key: key)
      let status = SecItemDelete(query as CFDictionary)

      if status != errSecSuccess && status != errSecItemNotFound {
        throw BiometricKeychainError.keychainError(status: status)
      }
    }

    private func baseQuery(key: String) -> [String: Any] {
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ]

      if let accessGroup {
        query[kSecAttrAccessGroup as String] = accessGroup
      }

      return query
    }
  }

  /// Errors specific to biometric keychain operations.
  public enum BiometricKeychainError: LocalizedError, Sendable {
    /// User canceled the biometric authentication.
    case userCanceled

    /// Biometric authentication failed.
    case authenticationFailed

    /// Failed to create access control.
    case accessControlCreationFailed(Error?)

    /// Keychain operation failed.
    case keychainError(status: OSStatus)

    public var errorDescription: String? {
      switch self {
      case .userCanceled:
        return "Biometric authentication was canceled."
      case .authenticationFailed:
        return "Biometric authentication failed."
      case .accessControlCreationFailed(let error):
        if let error {
          return "Failed to create access control: \(error.localizedDescription)"
        }
        return "Failed to create access control."
      case .keychainError(let status):
        return "Keychain error: \(status)"
      }
    }
  }

  // MARK: - Biometric Availability Check

  extension BiometricKeychainLocalStorage {
    /// Checks if biometric authentication is available on this device.
    ///
    /// - Returns: A tuple containing availability status and the biometry type.
    public static func checkBiometricAvailability() -> (
      isAvailable: Bool, biometryType: LABiometryType, error: Error?
    ) {
      let context = LAContext()
      var error: NSError?
      let available = context.canEvaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        error: &error
      )
      return (available, context.biometryType, error)
    }
  }
#endif
