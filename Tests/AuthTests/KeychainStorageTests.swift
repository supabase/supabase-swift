#if canImport(Security)
  import ConcurrencyExtras
  import Foundation
  import Security
  import Testing

  @testable import Auth

  @Suite
  struct KeychainStorageTests {
    @Test
    func defaultsKeepTheV2ServiceAndStayOnThisDevice() throws {
      let keychain = try #require(KeychainStorage().keychain as? Keychain)
      let query = keychain.setQuery(forKey: "key", data: Data())

      #expect(query[kSecAttrService as String] as? String == "supabase.gotrue.swift")
      #expect(query[kSecAttrAccessGroup as String] == nil)
      #expect(
        query[kSecAttrAccessible as String] as? String
          == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
      )
      #expect(query[kSecAttrSynchronizable as String] == nil)
      #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test
    func parametersReachTheQuery() throws {
      let storage = KeychainStorage(
        service: "custom",
        accessGroup: "group",
        accessibility: .whenUnlocked,
        synchronizable: true,
        useDataProtectionKeychain: false
      )
      let keychain = try #require(storage.keychain as? Keychain)
      let query = keychain.setQuery(forKey: "key", data: Data())

      #expect(query[kSecAttrService as String] as? String == "custom")
      #expect(query[kSecAttrAccessGroup as String] as? String == "group")
      #expect(
        query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlocked as String)
      #expect(query[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test
    func synchronizableItemsAreMatchedByEveryQuery() throws {
      let storage = KeychainStorage(accessibility: .afterFirstUnlock, synchronizable: true)
      let keychain = try #require(storage.keychain as? Keychain)

      #expect(keychain.baseQuery(withKey: "key")[kSecAttrSynchronizable as String] as? Bool == true)
      #expect(keychain.getOneQuery(byKey: "key")[kSecAttrSynchronizable as String] as? Bool == true)
      #expect(
        keychain.setQuery(forKey: "key", data: Data())[kSecAttrSynchronizable as String] as? Bool
          == true
      )
    }

    @Test(
      arguments: [
        (KeychainStorage.Accessibility.whenUnlocked, kSecAttrAccessibleWhenUnlocked as String),
        (.whenUnlockedThisDeviceOnly, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
        (.afterFirstUnlock, kSecAttrAccessibleAfterFirstUnlock as String),
        (
          .afterFirstUnlockThisDeviceOnly,
          kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        ),
        (.whenPasscodeSetThisDeviceOnly, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String),
      ] as [(KeychainStorage.Accessibility, String)]
    )
    func accessibilityMapsToItsSecurityConstant(
      _ accessibility: KeychainStorage.Accessibility,
      _ expected: String
    ) throws {
      let keychain = try #require(
        KeychainStorage(accessibility: accessibility).keychain as? Keychain)
      let query = keychain.setQuery(forKey: "key", data: Data())

      #expect(query[kSecAttrAccessible as String] as? String == expected)
    }

    @Test
    func roundTripsThroughTheKeychain() async throws {
      let fake = FakeKeychain()
      let storage = KeychainStorage(keychain: fake)

      try await storage.save(Data("session".utf8), key: "key")
      #expect(try await storage.load(key: "key") == Data("session".utf8))

      try await storage.remove(key: "key")
      #expect(try await storage.load(key: "key") == nil)
      #expect(fake.items.value.isEmpty)
    }

    @Test
    func missingEntitlementIsStorageMisconfigured() async {
      let error = KeychainError(code: .init(rawValue: errSecMissingEntitlement))
      let storage = KeychainStorage(
        keychain: FakeKeychain(readError: error, writeError: error, deleteError: error)
      )

      await expectAuthError(.storageMisconfigured) { _ = try await storage.load(key: "key") }
      await expectAuthError(.storageMisconfigured) { try await storage.save(Data(), key: "key") }
      await expectAuthError(.storageMisconfigured) { try await storage.remove(key: "key") }
    }

    @Test
    func interactionNotAllowedIsStorageUnavailable() async {
      let error = KeychainError(code: .interactionNotAllowed)
      let storage = KeychainStorage(
        keychain: FakeKeychain(readError: error, writeError: error, deleteError: error)
      )

      await expectAuthError(.storageUnavailable) { _ = try await storage.load(key: "key") }
      await expectAuthError(.storageUnavailable) { try await storage.save(Data(), key: "key") }
      await expectAuthError(.storageUnavailable) { try await storage.remove(key: "key") }
    }

    @Test
    func otherKeychainErrorsPropagateUnchanged() async {
      let storage = KeychainStorage(keychain: FakeKeychain(readError: KeychainError.authFailed))

      await #expect(throws: KeychainError.authFailed) {
        try await storage.load(key: "key")
      }
    }

    @Test
    func synchronizableWithDeviceIndependentAccessibilityIsAllowed() {
      _ = KeychainStorage(accessibility: .afterFirstUnlock, synchronizable: true)
      _ = KeychainStorage(accessibility: .whenUnlocked, synchronizable: true)
    }

    #if os(macOS)
      @Test
      func synchronizableWithThisDeviceOnlyAccessibilityTraps() async {
        await #expect(processExitsWith: .failure) {
          _ = KeychainStorage(accessibility: .afterFirstUnlockThisDeviceOnly, synchronizable: true)
        }
      }
    #endif

    private func expectAuthError(
      _ kind: AuthError.Kind,
      sourceLocation: SourceLocation = #_sourceLocation,
      _ operation: () async throws -> Void
    ) async {
      do {
        try await operation()
        Issue.record(
          "Expected AuthError with kind \(kind.rawValue)", sourceLocation: sourceLocation)
      } catch let error as AuthError {
        #expect(error.kind == kind, sourceLocation: sourceLocation)
        #expect(error.underlyingError is KeychainError, sourceLocation: sourceLocation)
      } catch {
        Issue.record("Expected AuthError, got \(error)", sourceLocation: sourceLocation)
      }
    }
  }
#endif
