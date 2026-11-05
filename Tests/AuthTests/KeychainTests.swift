#if canImport(Security)
  import ConcurrencyExtras
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
      let accessible = query[kSecAttrAccessible as String] as? String
      #expect(accessible == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test
    func writeMovesAnExistingItemToTheNewAccessibilityInPlace() throws {
      let store = FakeSecItemStore(
        items: [
          "key": .init(
            data: Data("old".utf8), accessible: kSecAttrAccessibleAfterFirstUnlock as String)
        ]
      )
      let keychain = Keychain(
        service: "service",
        accessibility: .afterFirstUnlockThisDeviceOnly,
        useDataProtectionKeychain: true,
        secItem: store.client
      )

      try keychain.set(Data("new".utf8), forKey: "key")

      #expect(store.calls.value == [.add, .update])
      #expect(
        store.items.value["key"]
          == .init(
            data: Data("new".utf8),
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
          )
      )
    }

    #if os(macOS)
      @Test
      func updateOnTheFileBasedKeychainOmitsAccessibility() {
        let keychain = Keychain(service: "service", accessibility: .afterFirstUnlockThisDeviceOnly)
        let attributes = keychain.updateAttributes(data: Data())
        #expect(attributes[kSecAttrAccessible as String] == nil)
      }
    #endif

  }

  /// An in-memory stand-in for the `SecItem` functions, keyed by `kSecAttrAccount`.
  ///
  /// It ignores every other attribute, so it models one service in one Keychain.
  final class FakeSecItemStore: Sendable {
    struct Item: Equatable {
      var data: Data
      var accessible: String?
    }

    enum Call: Equatable {
      case add, update, copy, delete
    }

    let items: LockIsolated<[String: Item]>
    let calls = LockIsolated<[Call]>([])

    init(items: [String: Item] = [:]) {
      self.items = LockIsolated(items)
    }

    var client: SecItemClient {
      SecItemClient(
        add: { query in
          self.calls.withValue { $0.append(.add) }
          let account = query[kSecAttrAccount as String] as! String
          let item = Item(
            data: query[kSecValueData as String] as! Data,
            accessible: query[kSecAttrAccessible as String] as? String
          )
          return self.items.withValue { items in
            guard items[account] == nil else { return errSecDuplicateItem }
            items[account] = item
            return errSecSuccess
          }
        },
        update: { query, attributes in
          self.calls.withValue { $0.append(.update) }
          let account = query[kSecAttrAccount as String] as! String
          let data = attributes[kSecValueData as String] as? Data
          let accessible = attributes[kSecAttrAccessible as String] as? String
          return self.items.withValue { items in
            guard var item = items[account] else { return errSecItemNotFound }
            if let data {
              item.data = data
            }
            if let accessible {
              item.accessible = accessible
            }
            items[account] = item
            return errSecSuccess
          }
        },
        copyMatching: { query in
          self.calls.withValue { $0.append(.copy) }
          let account = query[kSecAttrAccount as String] as! String
          guard let item = self.items.value[account] else { return (errSecItemNotFound, nil) }
          return (errSecSuccess, item.data as AnyObject)
        },
        delete: { query in
          self.calls.withValue { $0.append(.delete) }
          let account = query[kSecAttrAccount as String] as! String
          return self.items.withValue { items in
            items.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
          }
        }
      )
    }
  }
#endif
