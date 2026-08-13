import ConcurrencyExtras
import Foundation
import Logging

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
  var logger: Logging.Logger

  var resolvedEncoder: JSONEncoder { configuration.resolvedEncoder }
  var resolvedDecoder: JSONDecoder { configuration.resolvedDecoder }
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
