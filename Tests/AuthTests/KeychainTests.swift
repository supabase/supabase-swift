#if !os(Windows) && !os(Linux) && !os(Android)
  import Foundation
  import Security
  import Testing

  @testable import Auth

  @Suite
  struct KeychainTests {
    @Test
    func mapReadStatusItemNotFoundReturnsNil() throws {
      #expect(try Keychain.mapReadStatus(errSecItemNotFound, result: nil) == nil)
    }

    @Test
    func mapReadStatusSuccessReturnsData() throws {
      let data = Data("hello".utf8)
      #expect(try Keychain.mapReadStatus(errSecSuccess, result: data as AnyObject) == data)
    }

    @Test
    func mapReadStatusSuccessWithNonDataThrows() {
      #expect(throws: KeychainError.self) {
        try Keychain.mapReadStatus(errSecSuccess, result: "not data" as AnyObject)
      }
    }

    @Test
    func mapReadStatusFailureThrowsMappedError() {
      #expect(throws: KeychainError(code: .authFailed)) {
        try Keychain.mapReadStatus(errSecAuthFailed, result: nil)
      }
    }

    @Test
    func mapDeleteStatusItemNotFoundDoesNotThrow() throws {
      try Keychain.mapDeleteStatus(errSecItemNotFound)
    }

    @Test
    func mapDeleteStatusSuccessDoesNotThrow() throws {
      try Keychain.mapDeleteStatus(errSecSuccess)
    }

    @Test
    func mapDeleteStatusFailureThrows() {
      #expect(throws: KeychainError(code: .authFailed)) {
        try Keychain.mapDeleteStatus(errSecAuthFailed)
      }
    }

    @Test
    func baseQueryWithoutDataProtectionOmitsAttribute() {
      let keychain = Keychain(service: "service")
      let query = keychain.baseQuery(withKey: "key")
      #expect(query[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test
    func baseQueryWithDataProtectionSetsAttribute() {
      let keychain = Keychain(service: "service", useDataProtectionKeychain: true)
      let query = keychain.baseQuery(withKey: "key")
      #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test
    func getOneQueryCarriesDataProtectionAttribute() {
      let keychain = Keychain(service: "service", useDataProtectionKeychain: true)
      let query = keychain.getOneQuery(byKey: "key")
      #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test
    func setQueryCarriesDataProtectionAttribute() {
      let keychain = Keychain(service: "service", useDataProtectionKeychain: true)
      let query = keychain.setQuery(forKey: "key", data: Data())
      #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test
    func setQueryAccessibilityDefault() {
      let keychain = Keychain(service: "service")
      let query = keychain.setQuery(forKey: "key", data: Data())
      #if os(macOS)
        // The file-based Keychain ignores kSecAttrAccessible, so we must not send it.
        #expect(query[kSecAttrAccessible as String] == nil)
      #else
        #expect(query[kSecAttrAccessible as String] != nil)
      #endif
    }

    @Test
    func setQueryWithDataProtectionSetsAccessibility() {
      let keychain = Keychain(service: "service", useDataProtectionKeychain: true)
      let query = keychain.setQuery(forKey: "key", data: Data())
      #expect(query[kSecAttrAccessible as String] != nil)
    }
  }
#endif
