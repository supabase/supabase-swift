import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

struct CodeVerifierStorage: Sendable {
  var get: @Sendable () -> String?
  var set: @Sendable (_ code: String?) -> Void
}

extension CodeVerifierStorage {
  static let live: Self = {
    let code = LockIsolated(String?.none)

    return Self(
      get: { code.value },
      set: { code.setValue($0) }
    )
  }()
}
