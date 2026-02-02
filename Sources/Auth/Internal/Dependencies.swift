import ConcurrencyExtras
import Foundation

struct Dependencies: Sendable {
  var configuration: AuthClient.Configuration
  var http: any HTTPClientType
  var api: APIClient
  var codeVerifierStorage: CodeVerifierStorage
  var sessionStorage: SessionStorage
  var sessionManager: SessionManager

  var eventEmitter = AuthStateChangeEventEmitter()
  var date: @Sendable () -> Date = { Date() }

  var urlOpener: URLOpener = .live
  var pkce: PKCE = .live
  var logger: (any SupabaseLogger)?

  #if canImport(LocalAuthentication)
    var biometricAuthenticator: BiometricAuthenticator = .live
    var biometricStorage: BiometricStorage
    var biometricSession: BiometricSession
  #endif

  var encoder: JSONEncoder { configuration.encoder }
  var decoder: JSONDecoder { configuration.decoder }

  #if canImport(LocalAuthentication)
    init(
      configuration: AuthClient.Configuration,
      http: any HTTPClientType,
      api: APIClient,
      codeVerifierStorage: CodeVerifierStorage,
      sessionStorage: SessionStorage,
      sessionManager: SessionManager,
      eventEmitter: AuthStateChangeEventEmitter = AuthStateChangeEventEmitter(),
      date: @escaping @Sendable () -> Date = { Date() },
      urlOpener: URLOpener = .live,
      pkce: PKCE = .live,
      logger: (any SupabaseLogger)? = nil,
      biometricAuthenticator: BiometricAuthenticator = .live,
      biometricStorage: BiometricStorage,
      biometricSession: BiometricSession
    ) {
      self.configuration = configuration
      self.http = http
      self.api = api
      self.codeVerifierStorage = codeVerifierStorage
      self.sessionStorage = sessionStorage
      self.sessionManager = sessionManager
      self.eventEmitter = eventEmitter
      self.date = date
      self.urlOpener = urlOpener
      self.pkce = pkce
      self.logger = logger
      self.biometricAuthenticator = biometricAuthenticator
      self.biometricStorage = biometricStorage
      self.biometricSession = biometricSession
    }
  #else
    init(
      configuration: AuthClient.Configuration,
      http: any HTTPClientType,
      api: APIClient,
      codeVerifierStorage: CodeVerifierStorage,
      sessionStorage: SessionStorage,
      sessionManager: SessionManager,
      eventEmitter: AuthStateChangeEventEmitter = AuthStateChangeEventEmitter(),
      date: @escaping @Sendable () -> Date = { Date() },
      urlOpener: URLOpener = .live,
      pkce: PKCE = .live,
      logger: (any SupabaseLogger)? = nil
    ) {
      self.configuration = configuration
      self.http = http
      self.api = api
      self.codeVerifierStorage = codeVerifierStorage
      self.sessionStorage = sessionStorage
      self.sessionManager = sessionManager
      self.eventEmitter = eventEmitter
      self.date = date
      self.urlOpener = urlOpener
      self.pkce = pkce
      self.logger = logger
    }
  #endif
}

extension Dependencies {
  static let instances = LockIsolated([AuthClientID: Dependencies]())

  static subscript(_ id: AuthClientID) -> Dependencies {
    get {
      guard let instance = instances[id] else {
        fatalError("Dependencies not found for id: \(id)")
      }
      return instance
    }
    set {
      instances.withValue { $0[id] = newValue }
    }
  }
}
