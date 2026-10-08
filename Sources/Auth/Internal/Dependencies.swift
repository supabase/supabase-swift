import Foundation
import Logging

/// Everything an `AuthClient` needs, wired once by ``live(configuration:http:logger:date:pkce:urlOpener:)``.
///
/// Immutable on purpose. The test seams (`date`, `pkce`, `urlOpener`) are injected at
/// construction and never mutated afterwards, so plain `let` storage is enough and nothing needs a
/// lock or a process-global registry.
struct Dependencies: Sendable {
  let configuration: AuthClient.Configuration
  let http: HTTPClient
  /// Session-free requests. What `AuthAdmin` runs on.
  let api: APIClient
  /// Session-aware requests. What `AuthClient`, `AuthMFA`, and `AuthOAuthServer` run on.
  let sessionAPI: SessionAPIClient
  let codeVerifierStorage: CodeVerifierStorage
  let sessionStorage: SessionStorage
  let sessionManager: SessionManager
  let eventEmitter: AuthStateChangeEventEmitter
  let date: @Sendable () -> Date
  let urlOpener: URLOpener
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
    urlOpener: URLOpener = .live
  ) -> Dependencies {
    let http = http ?? HTTPClient(configuration: configuration)
    let logger = logger ?? configuration.logger
    let eventEmitter = AuthStateChangeEventEmitter(logger: logger)
    let api = APIClient(
      headers: configuration.headers, http: http, decoder: configuration.resolvedDecoder)
    let sessionStorage = SessionStorage.live(configuration: configuration)
    let sessionManager = SessionManager.live(
      configuration: configuration,
      api: api,
      sessionStorage: sessionStorage,
      eventEmitter: eventEmitter,
      logger: logger
    )

    return Dependencies(
      configuration: configuration,
      http: http,
      api: api,
      sessionAPI: SessionAPIClient(
        api: api, sessionManager: sessionManager, eventEmitter: eventEmitter),
      codeVerifierStorage: .live(configuration: configuration),
      sessionStorage: sessionStorage,
      sessionManager: sessionManager,
      eventEmitter: eventEmitter,
      date: date,
      urlOpener: urlOpener,
      pkce: pkce,
      logger: logger
    )
  }
}
