import _Helpers
import ConcurrencyExtras
import Foundation

struct Dependencies: Sendable {
  var configuration: AuthClient.Configuration
  var sessionManager: SessionManager
  var api: APIClient
  var eventEmitter: EventEmitter
  var sessionStorage: SessionStorage
  var sessionRefresher: SessionRefresher
  var codeVerifierStorage: CodeVerifierStorage
  var currentDate: @Sendable () -> Date = { Date() }
  var logger: (any SupabaseLogger)?
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

@propertyWrapper
struct Dependency<Value: Sendable>: Sendable {
  var wrappedValue: Value {
    Current[keyPath: keyPath.value]
  }

  let keyPath: UncheckedSendable<KeyPath<Dependencies, Value>>

  init(_ keyPath: KeyPath<Dependencies, Value>) {
    self.keyPath = UncheckedSendable(keyPath)
  }
}
