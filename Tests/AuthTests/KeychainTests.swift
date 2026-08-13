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
  }
#endif
