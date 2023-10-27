import Foundation
@_spi(Internal) import _Helpers

struct Dependencies {
  static let current = LockIsolated(Dependencies?.none)

  var configuration: GoTrueClient.Configuration
  var sessionManager: SessionManager
  var api: APIClient
  var eventEmitter: EventEmitter
  var sessionStorage: SessionStorage
  var sessionRefresher: SessionRefresher
}
