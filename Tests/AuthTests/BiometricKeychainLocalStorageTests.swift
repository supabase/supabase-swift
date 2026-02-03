//
//  BiometricKeychainLocalStorageTests.swift
//  Auth
//
//  Tests for BiometricKeychainLocalStorage
//

#if canImport(LocalAuthentication)
  import LocalAuthentication
  import XCTest

  @testable import Auth

  final class BiometricKeychainLocalStorageTests: XCTestCase {
    // MARK: - BiometricAccessControl Tests

    func testBiometricAccessControl_biometryOnly_flags() {
      let accessControl = BiometricAccessControl.biometryOnly
      XCTAssertEqual(accessControl.accessControlFlags, .biometryCurrentSet)
    }

    func testBiometricAccessControl_biometryOrPasscode_flags() {
      let accessControl = BiometricAccessControl.biometryOrPasscode
      XCTAssertEqual(accessControl.accessControlFlags, [.biometryCurrentSet, .or, .devicePasscode])
    }

    func testBiometricAccessControl_userPresence_flags() {
      let accessControl = BiometricAccessControl.userPresence
      XCTAssertEqual(accessControl.accessControlFlags, .userPresence)
    }

    // MARK: - BiometricKeychainError Tests

    func testBiometricKeychainError_userCanceled_description() {
      let error = BiometricKeychainError.userCanceled
      XCTAssertEqual(error.errorDescription, "Biometric authentication was canceled.")
    }

    func testBiometricKeychainError_authenticationFailed_description() {
      let error = BiometricKeychainError.authenticationFailed
      XCTAssertEqual(error.errorDescription, "Biometric authentication failed.")
    }

    func testBiometricKeychainError_accessControlCreationFailed_description() {
      let error = BiometricKeychainError.accessControlCreationFailed(nil)
      XCTAssertEqual(error.errorDescription, "Failed to create access control.")
    }

    func testBiometricKeychainError_accessControlCreationFailed_withError_description() {
      let underlyingError = NSError(
        domain: "test", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Test error"
        ])
      let error = BiometricKeychainError.accessControlCreationFailed(underlyingError)
      XCTAssertEqual(error.errorDescription, "Failed to create access control: Test error")
    }

    func testBiometricKeychainError_keychainError_description() {
      let error = BiometricKeychainError.keychainError(status: -25300)
      XCTAssertEqual(error.errorDescription, "Keychain error: -25300")
    }

    // MARK: - Initialization Tests

    func testInit_defaultValues() {
      let storage = BiometricKeychainLocalStorage()
      // Just verify it initializes without crashing
      XCTAssertNotNil(storage)
    }

    func testInit_customValues() {
      let storage = BiometricKeychainLocalStorage(
        service: "custom.service",
        accessGroup: "group.custom",
        accessControl: .biometryOnly,
        promptMessage: "Custom prompt"
      )
      XCTAssertNotNil(storage)
    }

    // MARK: - Biometric Availability Tests

    func testCheckBiometricAvailability_returnsResult() {
      let result = BiometricKeychainLocalStorage.checkBiometricAvailability()
      // On simulators, biometrics are typically not available
      // We just verify the function returns without crashing
      XCTAssertNotNil(result.biometryType)
    }
  }
#endif
