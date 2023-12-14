import ConcurrencyExtras
import Foundation

struct Dependencies: Sendable {
  static let current = LockIsolated(Dependencies?.none)

  var configuration: AuthClient.Configuration
  var sessionManager: SessionManager
  var api: APIClient
  var eventEmitter: EventEmitter
  var sessionStorage: SessionStorage
  var sessionRefresher: SessionRefresher
  var codeVerifierStorage: CodeVerifierStorage
}
