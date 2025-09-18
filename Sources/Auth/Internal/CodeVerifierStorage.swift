import Foundation

extension AuthClient {
  var codeVerifierKey: String { "\(configuration.storageKey ?? defaultStorageKey)-code-verifier" }

  func getCodeVerifier() -> String? {
    do {
      guard let data = try configuration.localStorage.retrieve(key: codeVerifierKey) else {
        configuration.logger?.debug("Code verifier not found.")
        return nil
      }
      return String(decoding: data, as: UTF8.self)
    } catch {
      configuration.logger?.error("Failure loading code verifier: \(error.localizedDescription)")
      return nil
    }
  }

  func setCodeVerifier(_ code: String?) {
    do {
      if let code, let data = code.data(using: .utf8) {
        try configuration.localStorage.store(key: codeVerifierKey, value: data)
      } else if code == nil {
        try configuration.localStorage.remove(key: codeVerifierKey)
      } else {
        configuration.logger?.error("Code verifier is not a valid UTF8 string.")
      }
    } catch {
      configuration.logger?.error(
        "Failure storing code verifier: \(error.localizedDescription)")
    }
  }
}
