import Foundation

extension AuthClient {
  /// Key used to store the PKCE code verifier in ``AuthLocalStorage``.
  ///
  /// Combines the base storage key with "-code-verifier" suffix.
  private var codeVerifierKey: String {
    "\(configuration.storageKey ?? defaultStorageKey)-code-verifier"
  }

  /// Retrieves the stored PKCE code verifier from local storage.
  func getStoredCodeVerifier() -> String? {
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

  /// Stores or removes a PKCE code verifier in local storage.
  func storeCodeVerifier(_ code: String?) {
    do {
      if let code, let data = code.data(using: .utf8) {
        try configuration.localStorage.store(key: codeVerifierKey, value: data)
      } else if code == nil {
        try configuration.localStorage.remove(key: codeVerifierKey)
      } else {
        configuration.logger?.error("Code verifier is not a valid UTF8 string.")
      }
    } catch {
      configuration.logger?.error("Failure storing code verifier: \(error.localizedDescription)")
    }
  }
}
