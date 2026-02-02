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

    // MARK: - BiometricStorage Tests

    func testBiometricStorage_initiallyDisabled() {
      let storage = BiometricStorage.mock

      XCTAssertFalse(storage.isEnabled)
      XCTAssertNil(storage.promptTitle)
    }

    func testBiometricStorage_enableWithDefaultPolicy() {
      let storage = BiometricStorage.mock

      storage.enable(.deviceOwnerAuthenticationWithBiometrics, .default, "Test Title")

      XCTAssertTrue(storage.isEnabled)
      XCTAssertEqual(storage.policy, .default)
      XCTAssertEqual(storage.evaluationPolicy, .deviceOwnerAuthenticationWithBiometrics)
      XCTAssertEqual(storage.promptTitle, "Test Title")
    }

    func testBiometricStorage_enableWithAlwaysPolicy() {
      let storage = BiometricStorage.mock

      storage.enable(.deviceOwnerAuthentication, .always, "Always Auth")

      XCTAssertTrue(storage.isEnabled)
      XCTAssertEqual(storage.policy, .always)
      XCTAssertEqual(storage.evaluationPolicy, .deviceOwnerAuthentication)
    }

    func testBiometricStorage_enableWithSessionPolicy() {
      let storage = BiometricStorage.mock

      storage.enable(
        .deviceOwnerAuthenticationWithBiometrics,
        .session(timeoutInSeconds: 300),
        "Session Auth"
      )

      XCTAssertTrue(storage.isEnabled)
      XCTAssertEqual(storage.policy, .session(timeoutInSeconds: 300))
    }

    func testBiometricStorage_enableWithAppLifecyclePolicy() {
      let storage = BiometricStorage.mock

      storage.enable(.deviceOwnerAuthenticationWithBiometrics, .appLifecycle, "App Lifecycle Auth")

      XCTAssertTrue(storage.isEnabled)
      XCTAssertEqual(storage.policy, .appLifecycle)
    }

    func testBiometricStorage_disable() {
      let storage = BiometricStorage.mock

      storage.enable(.deviceOwnerAuthenticationWithBiometrics, .default, "Test")
      XCTAssertTrue(storage.isEnabled)

      storage.disable()

      XCTAssertFalse(storage.isEnabled)
      XCTAssertNil(storage.policy)
      XCTAssertNil(storage.evaluationPolicy)
      XCTAssertNil(storage.promptTitle)
    }

    // MARK: - BiometricSession Tests

    func testBiometricSession_initiallyNoAuthTime() {
      let session = BiometricSession.mock

      XCTAssertNil(session.lastAuthenticationTime())
    }

    func testBiometricSession_recordAuthentication() {
      let lastAuthTime = LockIsolated<Date?>(nil)

      let session = BiometricSession(
        recordAuthentication: { lastAuthTime.setValue(Date()) },
        reset: { lastAuthTime.setValue(nil) },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { _ in lastAuthTime.value == nil }
      )

      XCTAssertNil(session.lastAuthenticationTime())

      session.recordAuthentication()

      XCTAssertNotNil(session.lastAuthenticationTime())
    }

    func testBiometricSession_reset() {
      let lastAuthTime = LockIsolated<Date?>(Date())

      let session = BiometricSession(
        recordAuthentication: { lastAuthTime.setValue(Date()) },
        reset: { lastAuthTime.setValue(nil) },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { _ in lastAuthTime.value == nil }
      )

      XCTAssertNotNil(session.lastAuthenticationTime())

      session.reset()

      XCTAssertNil(session.lastAuthenticationTime())
    }

    func testBiometricSession_defaultPolicy_requiresAuthOnFirstAccess() {
      let lastAuthTime = LockIsolated<Date?>(nil)

      let session = BiometricSession(
        recordAuthentication: { lastAuthTime.setValue(Date()) },
        reset: { lastAuthTime.setValue(nil) },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { policy in
          switch policy {
          case .default:
            return lastAuthTime.value == nil
          default:
            return false
          }
        }
      )

      XCTAssertTrue(session.isAuthenticationRequired(.default))

      session.recordAuthentication()

      XCTAssertFalse(session.isAuthenticationRequired(.default))
    }

    func testBiometricSession_alwaysPolicy_alwaysRequiresAuth() {
      let session = BiometricSession(
        recordAuthentication: {},
        reset: {},
        lastAuthenticationTime: { Date() },
        isAuthenticationRequired: { policy in
          switch policy {
          case .always:
            return true
          default:
            return false
          }
        }
      )

      XCTAssertTrue(session.isAuthenticationRequired(.always))
    }

    func testBiometricSession_sessionPolicy_requiresAuthAfterTimeout() {
      let lastAuthTime = LockIsolated<Date?>(Date().addingTimeInterval(-400))  // 400 seconds ago

      let session = BiometricSession(
        recordAuthentication: { lastAuthTime.setValue(Date()) },
        reset: { lastAuthTime.setValue(nil) },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { policy in
          switch policy {
          case .session(let timeout):
            guard let lastAuth = lastAuthTime.value else { return true }
            return Date().timeIntervalSince(lastAuth) > timeout
          default:
            return false
          }
        }
      )

      // With 300 second timeout and 400 seconds elapsed, should require auth
      XCTAssertTrue(session.isAuthenticationRequired(.session(timeoutInSeconds: 300)))

      // With 500 second timeout and 400 seconds elapsed, should not require auth
      XCTAssertFalse(session.isAuthenticationRequired(.session(timeoutInSeconds: 500)))
    }

    func testBiometricSession_sessionPolicy_noAuthTimeRequiresAuth() {
      let lastAuthTime = LockIsolated<Date?>(nil)

      let session = BiometricSession(
        recordAuthentication: { lastAuthTime.setValue(Date()) },
        reset: { lastAuthTime.setValue(nil) },
        lastAuthenticationTime: { lastAuthTime.value },
        isAuthenticationRequired: { policy in
          switch policy {
          case .session:
            return lastAuthTime.value == nil
          default:
            return false
          }
        }
      )

      XCTAssertTrue(session.isAuthenticationRequired(.session(timeoutInSeconds: 300)))
    }

    // MARK: - BiometricAuthenticator Tests

    func testBiometricAuthenticator_mockAvailable() {
      let authenticator = BiometricAuthenticator.mock(available: true, biometryType: .faceID)

      let availability = authenticator.checkAvailability()

      XCTAssertTrue(availability.isAvailable)
      XCTAssertEqual(availability.biometryType, .faceID)
      XCTAssertNil(availability.error)
    }

    func testBiometricAuthenticator_mockNotAvailable() {
      let authenticator = BiometricAuthenticator.mock(
        available: false,
        biometryType: .none,
        error: .notAvailable(reason: .noBiometryAvailable)
      )

      let availability = authenticator.checkAvailability()

      XCTAssertFalse(availability.isAvailable)
      XCTAssertEqual(availability.biometryType, .none)
      XCTAssertEqual(availability.error, .notAvailable(reason: .noBiometryAvailable))
    }

    func testBiometricAuthenticator_mockAuthenticationSuccess() async throws {
      let authenticator = BiometricAuthenticator.mock(shouldSucceed: true)

      // Should not throw
      try await authenticator.authenticate("Test", .deviceOwnerAuthenticationWithBiometrics)
    }

    func testBiometricAuthenticator_mockAuthenticationFailure() async {
      let authenticator = BiometricAuthenticator.mock(
        shouldSucceed: false,
        error: .userCancelled
      )

      do {
        try await authenticator.authenticate("Test", .deviceOwnerAuthenticationWithBiometrics)
        XCTFail("Expected authentication to fail")
      } catch let error as BiometricError {
        XCTAssertEqual(error, .userCancelled)
      } catch {
        XCTFail("Unexpected error type: \(error)")
      }
    }

    func testBiometricAuthenticator_touchID() {
      let authenticator = BiometricAuthenticator.mock(available: true, biometryType: .touchID)

      let availability = authenticator.checkAvailability()

      XCTAssertEqual(availability.biometryType, .touchID)
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
        authenticator: BiometricAuthenticator.mock(available: true, biometryType: .faceID)
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
        authenticator: BiometricAuthenticator.mock(available: true, shouldSucceed: true),
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
        authenticator: BiometricAuthenticator.mock(
          available: false,
          error: .notAvailable(reason: .noBiometryAvailable)
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
        authenticator: BiometricAuthenticator.mock(
          available: true,
          shouldSucceed: false,
          error: .userCancelled
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
      XCTAssertNotNil(BiometricError.notEnabled.errorDescription)
      XCTAssertNotNil(BiometricError.authenticationFailed(message: "test").errorDescription)
      XCTAssertNotNil(BiometricError.notAvailable(reason: .noBiometryAvailable).errorDescription)
    }

    func testBiometricUnavailableReason_descriptions() {
      XCTAssertFalse(BiometricUnavailableReason.noBiometryAvailable.localizedDescription.isEmpty)
      XCTAssertFalse(BiometricUnavailableReason.biometryNotEnrolled.localizedDescription.isEmpty)
      XCTAssertFalse(BiometricUnavailableReason.biometryLockout.localizedDescription.isEmpty)
      XCTAssertFalse(BiometricUnavailableReason.passcodeNotSet.localizedDescription.isEmpty)
      XCTAssertFalse(BiometricUnavailableReason.other(code: 123).localizedDescription.isEmpty)
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
        authenticator ?? BiometricAuthenticator.mock(available: true, shouldSucceed: true)

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
        authenticator ?? BiometricAuthenticator.mock(available: true, shouldSucceed: true)

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
