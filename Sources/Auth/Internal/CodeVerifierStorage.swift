import ConcurrencyExtras
import Foundation
import Helpers

struct CodeVerifierStorage: Sendable {
  var get: @Sendable () -> String?
  var set: @Sendable (_ code: String?) -> Void
}

extension CodeVerifierStorage {
  static func live(clientID: AuthClientID) -> Self {
    var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
    var key: String { "\(configuration.storageKey ?? defaultStorageKey)-code-verifier" }

    return Self(
      get: {
        do {
          guard let data = try configuration.localStorage.retrieve(key: key) else {
            configuration.logger?.debug("Code verifier not found.")
            return nil
          }
          return String(decoding: data, as: UTF8.self)
        } catch {
          configuration.logger?.error("Failure loading code verifier: \(error.localizedDescription)")
          return nil
        }
      },
      set: { code in
        do {
          if let code, let data = code.data(using: .utf8) {
            try configuration.localStorage.store(key: key, value: data)
          } else if code == nil {
            try configuration.localStorage.remove(key: key)
          } else {
            configuration.logger?.error("Code verifier is not a valid UTF8 string.")
          }
        } catch {
          configuration.logger?.error("Failure storing code verifier: \(error.localizedDescription)")
        }
      }
    )
  }
}
