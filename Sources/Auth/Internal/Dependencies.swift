import Foundation
import Logging

/// Everything an `AuthClient` needs, wired once by ``live(configuration:http:logger:date:pkce:platform:beforeRefreshingHeldSession:)``.
///
/// Immutable on purpose. The test seams (`date`, `pkce`, `platform`) are injected at
/// construction and never mutated afterwards, so plain `let` storage is enough and nothing needs a
/// lock or a process-global registry.
struct Dependencies: Sendable {
  let configuration: AuthClient.Configuration
  let http: HTTPClient
  /// Builds every request and decodes every response.
  let authAPI: AuthAPI
  /// Session-free requests. What `AuthAdmin` runs on.
  let api: APIClient
  /// Session-aware requests. What `AuthClient`, `AuthMFA`, and `AuthOAuthServer` run on.
  let sessionAPI: SessionAPIClient
  let codeVerifierStorage: CodeVerifierStorage
  /// Owns the session. Shared with every other client for the same project and storage key.
  let sessionStore: SessionStore
  let sessionManager: SessionManager
  let autoRefresh: AutoRefreshController
  let date: @Sendable () -> Date
  let platform: AuthPlatform
  let pkce: PKCE
  let logger: Logging.Logger

  var resolvedEncoder: JSONEncoder { configuration.resolvedEncoder }
  var resolvedDecoder: JSONDecoder { configuration.resolvedDecoder }
}

extension Dependencies {
  static func live(
    configuration: AuthClient.Configuration,
    http: HTTPClient? = nil,
    logger: Logging.Logger? = nil,
    date: @escaping @Sendable () -> Date = { Date() },
    pkce: PKCE = .live,
    platform: AuthPlatform = .live,
    beforeRefreshingHeldSession: @escaping @Sendable () async -> Void = {}
  ) -> Dependencies {
    let http = http ?? HTTPClient(configuration: configuration)
    let logger = logger ?? configuration.logger
    let authAPI = AuthAPI(
      url: configuration.url,
      headers: configuration.headers,
      defaultRedirectURL: configuration.redirectToURL,
      encoder: configuration.resolvedEncoder,
      decoder: configuration.resolvedDecoder
    )
    let api = APIClient(http: http)
    let storageKey = configuration.storageKey ?? defaultStorageKey
    let localStorage = MisconfigurationReportingStorage(configuration.localStorage)
    let sessionStore = SessionStore.shared(
      url: configuration.url,
      storageKey: storageKey,
      storage: AuthLocalStorageAdapter(localStorage: localStorage),
      now: date,
      initialLoad: { try PersistedSessionLoader.load(from: localStorage, key: storageKey) }
    )
    let refresh: @Sendable (_ refreshToken: String) async throws -> Session = { refreshToken in
      try await api.execute(authAPI.refreshSession(refreshToken: refreshToken))
    }
    let sessionManager = SessionManager.live(
      policy: configuration.autoRefresh,
      sessionStore: sessionStore,
      logger: logger,
      request: refresh,
      beforeRefreshingHeldSession: beforeRefreshingHeldSession
    )
    let autoRefresh = AutoRefreshController(
      policy: configuration.autoRefresh,
      startsInForeground: !(configuration.observesAppLifecycle && platform.hasBackgroundState),
      store: sessionStore,
      driver: Refresher.Driver(clock: configuration.clock, logger: logger, request: refresh)
    )

    return Dependencies(
      configuration: configuration,
      http: http,
      authAPI: authAPI,
      api: api,
      sessionAPI: SessionAPIClient(
        api: api, sessionManager: sessionManager, sessionStore: sessionStore),
      codeVerifierStorage: .live(configuration: configuration, localStorage: localStorage),
      sessionStore: sessionStore,
      sessionManager: sessionManager,
      autoRefresh: autoRefresh,
      date: date,
      platform: platform,
      pkce: pkce,
      logger: logger
    )
  }
}
