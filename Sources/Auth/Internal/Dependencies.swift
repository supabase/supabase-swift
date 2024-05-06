import _Helpers
import ConcurrencyExtras
import Foundation

struct Dependencies: Sendable {
  var configuration: AuthClient.Configuration
  var sessionRefresher: SessionRefresher
  var http: any HTTPClientType
  var sessionManager = SessionManager()
  var api = APIClient()

  var eventEmitter: AuthStateChangeEventEmitter = .shared
  var date: @Sendable () -> Date = { Date() }
  var codeVerifierStorage = CodeVerifierStorage.live

  var encoder: JSONEncoder { configuration.encoder }
  var decoder: JSONDecoder { configuration.decoder }
  var logger: (any SupabaseLogger)? { configuration.logger }
}

private let _Current = LockIsolated<Dependencies?>(nil)
var Current: Dependencies {
  get {
    guard let instance = _Current.value else {
      fatalError("Current should be set before usage.")
    }

    return instance
  }
  set {
    _Current.withValue { Current in
      Current = newValue
    }
  }
}
