@_spi(Internal) import _Helpers
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
  var currentDate: @Sendable () -> Date = { Date() }
  var logger: SupabaseLogger?
}
