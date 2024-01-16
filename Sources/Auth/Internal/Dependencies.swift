import Foundation

struct Dependencies: Sendable {
  static let current = LockedState(initialState: Dependencies?.none)

  var configuration: AuthClient.Configuration
  var sessionManager: SessionManager
  var api: APIClient
  var eventEmitter: EventEmitter
  var sessionStorage: SessionStorage
  var sessionRefresher: SessionRefresher
  var codeVerifierStorage: CodeVerifierStorage
  var currentDate: @Sendable () -> Date = { Date() }
}
