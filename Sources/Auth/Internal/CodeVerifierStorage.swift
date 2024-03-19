import Foundation
@_spi(Internal) import _Helpers

struct CodeVerifierStorage: Sendable {
  var getCodeVerifier: @Sendable () throws -> String?
  var storeCodeVerifier: @Sendable (_ code: String) throws -> Void
  var deleteCodeVerifier: @Sendable () throws -> Void
}

extension CodeVerifierStorage {
  static var live: Self = {
    var localStorage: any AuthLocalStorage {
      Dependencies.current.value!.configuration.localStorage
    }

    let key = "supabase.code-verifier"

    return Self(
      getCodeVerifier: {
        try localStorage.retrieve(key: key).flatMap {
          String(data: $0, encoding: .utf8)
        }
      },
      storeCodeVerifier: { code in
        try localStorage.store(key: key, value: Data(code.utf8))
      },
      deleteCodeVerifier: {
        try localStorage.remove(key: key)
      }
    )
  }()
}
