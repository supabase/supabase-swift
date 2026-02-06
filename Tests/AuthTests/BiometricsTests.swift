//
//  BiometricsTests.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import ConcurrencyExtras
  import CustomDump
  import LocalAuthentication
  import TestHelpers
  import XCTest

  @testable import Auth

  final class BiometricsTests: XCTestCase {
    var http: HTTPClientMock!
    var localStorage: InMemoryLocalStorage!

    override func setUp() {
      super.setUp()
      http = HTTPClientMock()
      localStorage = InMemoryLocalStorage()
    }

    // MARK: - withBiometrics Tests

    func testWithBiometrics_disabled_executesOperationDirectly() async throws {
      let clientID = setupDependencies(biometricsEnabled: false)

      let operationCalled = LockIsolated(false)
      let result = try await withBiometrics(clientID: clientID) {
        operationCalled.setValue(true)
        return "success"
      }

      XCTAssertTrue(operationCalled.value)
      XCTAssertEqual(result, "success")
    }

    func testWithBiometrics_enabled_authNotRequired_executesOperation() async throws {
      let clientID = setupDependencies(
        biometricsEnabled: true,
        policy: .default,
        authRequired: false
      )

      let operationCalled = LockIsolated(false)
      let result = try await withBiometrics(clientID: clientID) {
        operationCalled.setValue(true)
        return 42
      }

      XCTAssertTrue(operationCalled.value)
      XCTAssertEqual(result, 42)
    }

    func testWithBiometrics_enabled_authRequired_authenticatesAndExecutes() async throws {
      let authCalled = LockIsolated(false)
      let authRecorded = LockIsolated(false)

      let clientID = setupDependencies(
        biometricsEnabled: true,
        policy: .always,
        authRequired: true,
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in
            authCalled.setValue(true)
          }
        ),
        sessionRecordAuth: { authRecorded.setValue(true) }
      )

      let operationCalled = LockIsolated(false)
      _ = try await withBiometrics(clientID: clientID) {
        operationCalled.setValue(true)
        return "done"
      }

      XCTAssertTrue(authCalled.value, "Authentication should be called")
      XCTAssertTrue(authRecorded.value, "Authentication should be recorded")
      XCTAssertTrue(operationCalled.value, "Operation should be called")
    }

    func testWithBiometrics_authenticationFails_throwsError() async {
      let clientID = setupDependencies(
        biometricsEnabled: true,
        policy: .always,
        authRequired: true,
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in
            throw BiometricError.userCancelled
          }
        )
      )

      do {
        _ = try await withBiometrics(clientID: clientID) {
          XCTFail("Operation should not be called when authentication fails")
          return "should not reach"
        }
        XCTFail("Expected error to be thrown")
      } catch let error as BiometricError {
        XCTAssertEqual(error, .userCancelled)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    // MARK: - AuthClient Biometrics Extension Tests

    func testAuthClient_biometricsAvailability() {
      let client = makeAuthClient(
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in }
        )
      )

      let availability = client.biometricsAvailability()

      XCTAssertTrue(availability.isAvailable)
      XCTAssertEqual(availability.biometryType, .faceID)
    }

    func testAuthClient_isBiometricsEnabled_initiallyFalse() {
      let client = makeAuthClient(biometricsEnabled: false)

      XCTAssertFalse(client.isBiometricsEnabled)
    }

    func testAuthClient_enableBiometrics_success() async throws {
      let enableCalled = LockIsolated(false)
      let storage = makeBiometricStorage(
        isEnabled: false,
        onEnable: { _, _, _ in enableCalled.setValue(true) }
      )

      let client = makeAuthClient(
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in }
        ),
        storage: storage
      )

      try await client.enableBiometrics(
        title: "Test Enable",
        evaluationPolicy: .deviceOwnerAuthenticationWithBiometrics,
        policy: .default
      )

      XCTAssertTrue(enableCalled.value)
    }

    func testAuthClient_enableBiometrics_notAvailable_throws() async {
      let client = makeAuthClient(
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(
              isAvailable: false,
              biometryType: .none,
              error: .notAvailable(reason: .noBiometryAvailable)
            )
          },
          authenticate: { _, _ in }
        )
      )

      do {
        try await client.enableBiometrics()
        XCTFail("Expected error when biometrics not available")
      } catch let error as BiometricError {
        if case .notAvailable = error {
          // Expected
        } else {
          XCTFail("Expected notAvailable error, got: \(error)")
        }
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    func testAuthClient_enableBiometrics_authFails_throws() async {
      let client = makeAuthClient(
        authenticator: BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in
            throw BiometricError.userCancelled
          }
        )
      )

      do {
        try await client.enableBiometrics()
        XCTFail("Expected error when authentication fails")
      } catch let error as BiometricError {
        XCTAssertEqual(error, .userCancelled)
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    func testAuthClient_disableBiometrics() {
      let disableCalled = LockIsolated(false)
      let resetCalled = LockIsolated(false)

      let storage = makeBiometricStorage(
        isEnabled: true,
        onDisable: { disableCalled.setValue(true) }
      )
      let session = makeBiometricSession(onReset: { resetCalled.setValue(true) })

      let client = makeAuthClient(storage: storage, session: session)
      client.disableBiometrics()

      XCTAssertTrue(disableCalled.value)
      XCTAssertTrue(resetCalled.value)
    }

    func testAuthClient_isBiometricAuthenticationRequired_disabled() {
      let client = makeAuthClient(biometricsEnabled: false)

      XCTAssertFalse(client.isBiometricAuthenticationRequired())
    }

    func testAuthClient_isBiometricAuthenticationRequired_enabled() {
      let client = makeAuthClient(
        biometricsEnabled: true,
        policy: .always,
        authRequired: true
      )

      XCTAssertTrue(client.isBiometricAuthenticationRequired())
    }

    func testAuthClient_invalidateBiometricSession() {
      let resetCalled = LockIsolated(false)
      let session = makeBiometricSession(onReset: { resetCalled.setValue(true) })

      let client = makeAuthClient(session: session)
      client.invalidateBiometricSession()

      XCTAssertTrue(resetCalled.value)
    }

    // MARK: - BiometricError Tests

    func testBiometricError_errorDescriptions() {
      XCTAssertNotNil(BiometricError.userCancelled.errorDescription)
      XCTAssertNotNil(BiometricError.notEnrolled.errorDescription)
      XCTAssertNotNil(BiometricError.lockedOut.errorDescription)
      XCTAssertNotNil(BiometricError.authenticationFailed(message: "test").errorDescription)
      XCTAssertNotNil(BiometricError.notAvailable(reason: .noBiometryAvailable).errorDescription)
    }

    func testBiometricUnavailableReason_descriptions() {
      XCTAssertFalse(BiometricUnavailableReason.noBiometryAvailable.localizedDescription.isEmpty)
      XCTAssertFalse(BiometricUnavailableReason.passcodeNotSet.localizedDescription.isEmpty)
    }

    // MARK: - BiometricPolicy Equality Tests

    func testBiometricPolicy_equality() {
      XCTAssertEqual(BiometricPolicy.default, BiometricPolicy.default)
      XCTAssertEqual(BiometricPolicy.always, BiometricPolicy.always)
      XCTAssertEqual(BiometricPolicy.appLifecycle, BiometricPolicy.appLifecycle)
      XCTAssertEqual(
        BiometricPolicy.session(timeoutInSeconds: 300),
        BiometricPolicy.session(timeoutInSeconds: 300)
      )
      XCTAssertNotEqual(
        BiometricPolicy.session(timeoutInSeconds: 300),
        BiometricPolicy.session(timeoutInSeconds: 600)
      )
      XCTAssertNotEqual(BiometricPolicy.default, BiometricPolicy.always)
    }

    // MARK: - BiometricEvaluationPolicy Tests

    func testBiometricEvaluationPolicy_laPolicy() {
      XCTAssertEqual(
        BiometricEvaluationPolicy.deviceOwnerAuthenticationWithBiometrics.laPolicy,
        .deviceOwnerAuthenticationWithBiometrics
      )
      XCTAssertEqual(
        BiometricEvaluationPolicy.deviceOwnerAuthentication.laPolicy,
        .deviceOwnerAuthentication
      )
    }

    // MARK: - Helpers

    @discardableResult
    private func setupDependencies(
      biometricsEnabled: Bool = false,
      policy: BiometricPolicy? = nil,
      authRequired: Bool = false,
      authenticator: BiometricAuthenticator? = nil,
      storage: BiometricStorage? = nil,
      session: BiometricSession? = nil,
      sessionRecordAuth: (() -> Void)? = nil
    ) -> AuthClientID {
      let finalStorage =
        storage ?? makeBiometricStorage(isEnabled: biometricsEnabled, policy: policy)
      let finalSession =
        session
        ?? makeBiometricSession(authRequired: authRequired, onRecordAuth: sessionRecordAuth)
      let finalAuthenticator =
        authenticator
        ?? BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in }
        )

      // Create AuthClient first - this sets up dependencies
      let configuration = AuthClient.Configuration(
        url: URL(string: "https://test.supabase.co")!,
        localStorage: localStorage,
        logger: nil
      )
      let client = AuthClient(configuration: configuration)
      let clientID = client.clientID

      // Then modify the biometric dependencies
      Dependencies[clientID].biometricAuthenticator = finalAuthenticator
      Dependencies[clientID].biometricStorage = finalStorage
      Dependencies[clientID].biometricSession = finalSession

      return clientID
    }

    private func makeAuthClient(
      biometricsEnabled: Bool = false,
      policy: BiometricPolicy? = nil,
      authRequired: Bool = false,
      authenticator: BiometricAuthenticator? = nil,
      storage: BiometricStorage? = nil,
      session: BiometricSession? = nil
    ) -> AuthClient {
      let configuration = AuthClient.Configuration(
        url: URL(string: "https://test.supabase.co")!,
        localStorage: localStorage,
        logger: nil
      )

      let client = AuthClient(configuration: configuration)

      let finalStorage =
        storage ?? makeBiometricStorage(isEnabled: biometricsEnabled, policy: policy)
      let finalSession = session ?? makeBiometricSession(authRequired: authRequired)
      let finalAuthenticator =
        authenticator
        ?? BiometricAuthenticator(
          checkAvailability: {
            BiometricAvailability(isAvailable: true, biometryType: .faceID, error: nil)
          },
          authenticate: { _, _ in }
        )

      Dependencies[client.clientID].biometricAuthenticator = finalAuthenticator
      Dependencies[client.clientID].biometricStorage = finalStorage
      Dependencies[client.clientID].biometricSession = finalSession

      return client
    }

    private func makeBiometricStorage(
      isEnabled: Bool = false,
      policy: BiometricPolicy? = nil,
      evaluationPolicy: BiometricEvaluationPolicy? = nil,
      promptTitle: String? = nil,
      onEnable: ((BiometricEvaluationPolicy, BiometricPolicy, String) -> Void)? = nil,
      onDisable: (() -> Void)? = nil
    ) -> BiometricStorage {
      let _isEnabled = LockIsolated(isEnabled)
      let _policy = LockIsolated(policy)
      let _evalPolicy = LockIsolated(evaluationPolicy)
      let _title = LockIsolated(promptTitle)

      return BiometricStorage(
        getIsEnabled: { _isEnabled.value },
        getPolicy: { _policy.value },
        getEvaluationPolicy: { _evalPolicy.value },
        getPromptTitle: { _title.value },
        enable: { evalPolicy, biometricPolicy, title in
          _isEnabled.setValue(true)
          _policy.setValue(biometricPolicy)
          _evalPolicy.setValue(evalPolicy)
          _title.setValue(title)
          onEnable?(evalPolicy, biometricPolicy, title)
        },
        disable: {
          _isEnabled.setValue(false)
          _policy.setValue(nil)
          _evalPolicy.setValue(nil)
          _title.setValue(nil)
          onDisable?()
        }
      )
    }

    private func makeBiometricSession(
      authRequired: Bool = false,
      onRecordAuth: (() -> Void)? = nil,
      onReset: (() -> Void)? = nil
    ) -> BiometricSession {
      let lastAuthTime = LockIsolated<Date?>(nil)

      return BiometricSession(
        recordAuthentication: {
          lastAuthTime.setValue(Date())
          onRecordAuth?()
        },
        reset: {
          lastAuthTime.setValue(nil)
          onReset?()
        },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { _ in authRequired }
      )
    }
  }
#endif
