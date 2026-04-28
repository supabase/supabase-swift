import ConcurrencyExtras
import Foundation
import TestHelpers

@testable import Auth

#if canImport(LocalAuthentication)
  import LocalAuthentication
#endif

func json(named name: String) -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: "json")
  return try! Data(contentsOf: url!)
}

extension Decodable {
  init(fromMockNamed name: String) {
    self = try! AuthClient.Configuration.jsonDecoder.decode(Self.self, from: json(named: name))
  }
}

extension CodeVerifierStorage {
  static var mock: CodeVerifierStorage {
    let code = LockIsolated<String?>(nil)

    return Self(
      get: { code.value },
      set: { code.setValue($0) }
    )
  }
}

extension SessionStorage {
  static var mock: SessionStorage {
    let session = LockIsolated<Session?>(nil)
    return SessionStorage(
      get: { session.value },
      store: { session.setValue($0) },
      delete: { session.setValue(nil) }
    )
  }
}

extension SessionManager {
  static var mock: SessionManager {
    SessionManager(
      session: { throw AuthError.sessionMissing },
      refreshSession: { _ in throw AuthError.sessionMissing },
      update: { _ in },
      remove: {},
      startAutoRefresh: {},
      stopAutoRefresh: {}
    )
  }
}

#if canImport(LocalAuthentication)
  extension BiometricStorage {
    static var mock: BiometricStorage {
      let isEnabled = LockIsolated(false)
      let policy = LockIsolated<BiometricPolicy?>(.default)
      let evaluationPolicy = LockIsolated<BiometricEvaluationPolicy?>(
        .deviceOwnerAuthenticationWithBiometrics)
      let promptTitle = LockIsolated<String?>(nil)

      return BiometricStorage(
        getIsEnabled: { isEnabled.value },
        getPolicy: { policy.value },
        getEvaluationPolicy: { evaluationPolicy.value },
        getPromptTitle: { promptTitle.value },
        enable: { evalPolicy, biometricPolicy, title in
          isEnabled.setValue(true)
          policy.setValue(biometricPolicy)
          evaluationPolicy.setValue(evalPolicy)
          promptTitle.setValue(title)
        },
        disable: {
          isEnabled.setValue(false)
          policy.setValue(nil)
          evaluationPolicy.setValue(nil)
          promptTitle.setValue(nil)
        }
      )
    }
  }

  extension BiometricSession {
    static var mock: BiometricSession {
      let lastAuthTime = LockIsolated<Date?>(nil)

      return BiometricSession(
        recordAuthentication: {
          lastAuthTime.setValue(Date())
        },
        reset: {
          lastAuthTime.setValue(nil)
        },
        lastAuthenticationTime: {
          lastAuthTime.value
        },
        isAuthenticationRequired: { _ in
          false
        }
      )
    }
  }

  extension Dependencies {
    static func makeMock() -> Dependencies {
      Dependencies(
        configuration: AuthClient.Configuration(
          url: URL(string: "https://project-id.supabase.com")!,
          localStorage: InMemoryLocalStorage(),
          logger: nil
        ),
        http: HTTPClientMock(),
        api: APIClient(clientID: AuthClientID()),
        codeVerifierStorage: CodeVerifierStorage.mock,
        sessionStorage: SessionStorage.mock,
        sessionManager: SessionManager.mock,
        biometricStorage: BiometricStorage.mock,
        biometricSession: BiometricSession.mock
      )
    }
  }
#else
  extension Dependencies {
    static func makeMock() -> Dependencies {
      Dependencies(
        configuration: AuthClient.Configuration(
          url: URL(string: "https://project-id.supabase.com")!,
          localStorage: InMemoryLocalStorage(),
          logger: nil
        ),
        http: HTTPClientMock(),
        api: APIClient(clientID: AuthClientID()),
        codeVerifierStorage: CodeVerifierStorage.mock,
        sessionStorage: SessionStorage.mock,
        sessionManager: SessionManager.mock
      )
    }
  }
#endif
