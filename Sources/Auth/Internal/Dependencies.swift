import ConcurrencyExtras
import Foundation
import Helpers

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

  var encoder: JSONEncoder { configuration.encoder }
  var decoder: JSONDecoder { configuration.decoder }
  var logger: (any SupabaseLogger)? { configuration.logger }
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
