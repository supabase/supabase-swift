#if canImport(Security)
  import ConcurrencyExtras
  import Foundation
  import Testing

  @testable import Auth

  @Suite
  struct KeychainStorageMigrationTests {
    #if os(macOS)
      @Test
      func dataProtectionKeychainProbesTheFileBasedLocationWithSameServiceAndGroup() throws {
        let storage = KeychainStorage(service: "custom", accessGroup: "group")
        let primary = try #require(storage.keychain as? Keychain)
        let legacy = try #require(storage.legacyKeychains.first as? Keychain)

        #expect(primary.useDataProtectionKeychain)
        #expect(storage.legacyKeychains.count == 1)
        #expect(legacy.service == "custom")
        #expect(legacy.accessGroup == "group")
        #expect(!legacy.useDataProtectionKeychain)
      }
    #endif

    @Test
    func fileBasedKeychainHasNothingToMigrate() {
      let storage = KeychainStorage(useDataProtectionKeychain: false)
      #expect(storage.legacyKeychains.isEmpty)
    }

    @Test
    func sharedTargetsMigrateOnceIntoOneLocation() async throws {
      let session = Data("session".utf8)
      let primary = FakeKeychain()
      let legacy = FakeKeychain(items: ["key": session])
      let widget = KeychainStorage(keychain: primary, legacyKeychains: [legacy])
      let app = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try await widget.load(key: "key") == session)
      #expect(legacy.items.value["key"] == nil)
      #expect(try await app.load(key: "key") == session)
    }

    @Test
    func loadMigratesFromLegacyLocation() async throws {
      let value = Data("session".utf8)
      let primary = FakeKeychain()
      let legacy = FakeKeychain(items: ["key": value])
      let storage = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try await storage.load(key: "key") == value)
      #expect(primary.items.value["key"] == value)
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func loadPrefersPrimaryAndLeavesLegacyUntouched() async throws {
      let primaryValue = Data("new".utf8)
      let legacyValue = Data("old".utf8)
      let primary = FakeKeychain(items: ["key": primaryValue])
      let legacy = FakeKeychain(items: ["key": legacyValue])
      let storage = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try await storage.load(key: "key") == primaryValue)
      #expect(legacy.items.value["key"] == legacyValue)
    }

    @Test
    func loadProbesLegacyLocationsInOrder() async throws {
      let first = FakeKeychain(items: ["key": Data("first".utf8)])
      let second = FakeKeychain(items: ["key": Data("second".utf8)])
      let primary = FakeKeychain()
      let storage = KeychainStorage(
        keychain: primary,
        legacyKeychains: [first, second]
      )

      #expect(try await storage.load(key: "key") == Data("first".utf8))
      #expect(primary.items.value["key"] == Data("first".utf8))
      #expect(first.items.value["key"] == nil)
      #expect(second.items.value["key"] == Data("second".utf8))
    }

    @Test
    func loadMissingEverywhereReturnsNil() async throws {
      let storage = KeychainStorage(
        keychain: FakeKeychain(),
        legacyKeychains: [FakeKeychain()]
      )
      #expect(try await storage.load(key: "key") == nil)
    }

    @Test
    func loadPropagatesLegacyProbeFailure() async {
      struct ProbeFailure: Error {}
      let storage = KeychainStorage(
        keychain: FakeKeychain(),
        legacyKeychains: [FakeKeychain(readError: ProbeFailure())]
      )

      await #expect(throws: ProbeFailure.self) {
        try await storage.load(key: "key")
      }
    }

    @Test
    func loadPropagatesPrimaryFailure() async {
      struct PrimaryFailure: Error {}
      let storage = KeychainStorage(
        keychain: FakeKeychain(readError: PrimaryFailure()),
        legacyKeychains: []
      )
      await #expect(throws: PrimaryFailure.self) {
        try await storage.load(key: "key")
      }
    }

    @Test
    func removeClearsPrimaryAndLegacyLocations() async throws {
      let primary = FakeKeychain(items: ["key": Data()])
      let legacy = FakeKeychain(items: ["key": Data()])
      let storage = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      try await storage.remove(key: "key")

      #expect(primary.items.value["key"] == nil)
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func removeClearsLegacyLocationsEvenWhenPrimaryDeleteFails() async {
      struct DeleteFailure: Error {}
      let primary = FakeKeychain(items: ["key": Data()], deleteError: DeleteFailure())
      let legacy = FakeKeychain(items: ["key": Data()])
      let storage = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      await #expect(throws: DeleteFailure.self) {
        try await storage.remove(key: "key")
      }
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func loadReturnsLegacyValueAndKeepsItWhenPrimaryWriteFails() async throws {
      struct WriteFailure: Error {}
      let legacyValue = Data("session".utf8)
      let primary = FakeKeychain(writeError: WriteFailure())
      let legacy = FakeKeychain(items: ["key": legacyValue])
      let storage = KeychainStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try await storage.load(key: "key") == legacyValue)
      #expect(legacy.items.value["key"] == legacyValue)
      #expect(primary.items.value["key"] == nil)
    }

    @Test(arguments: [
      (errSecMissingEntitlement, AuthError.Kind.storageMisconfigured),
      (errSecInteractionNotAllowed, AuthError.Kind.storageUnavailable),
    ])
    func keychainStatusesAnAppHandlesBecomeAuthErrors(status: OSStatus, kind: AuthError.Kind) async
    {
      let error = KeychainError(code: .init(rawValue: status))
      let storage = KeychainStorage(
        keychain: FakeKeychain(readError: error, writeError: error, deleteError: error),
        legacyKeychains: []
      )

      for operation in [
        { _ = try await storage.load(key: "key") },
        { try await storage.save(Data(), key: "key") },
        { try await storage.remove(key: "key") },
      ] as [@Sendable () async throws -> Void] {
        let thrown = await #expect(throws: AuthError.self) { try await operation() }
        #expect(thrown?.kind == kind)
        #expect(thrown?.underlyingError is KeychainError)
      }
    }

    @Test
    func legacyProbeThatIsLockedIsStorageUnavailable() async {
      let storage = KeychainStorage(
        keychain: FakeKeychain(),
        legacyKeychains: [FakeKeychain(readError: KeychainError.interactionNotAllowed)]
      )

      let thrown = await #expect(throws: AuthError.self) { try await storage.load(key: "key") }
      #expect(thrown?.kind == .storageUnavailable)
    }
  }

  final class FakeKeychain: KeychainProtocol, @unchecked Sendable {
    let items: LockIsolated<[String: Data]>
    let readError: (any Error)?
    let writeError: (any Error)?
    let deleteError: (any Error)?

    init(
      items: [String: Data] = [:],
      readError: (any Error)? = nil,
      writeError: (any Error)? = nil,
      deleteError: (any Error)? = nil
    ) {
      self.items = LockIsolated(items)
      self.readError = readError
      self.writeError = writeError
      self.deleteError = deleteError
    }

    func data(forKey key: String) throws -> Data? {
      if let readError {
        throw readError
      }
      return items.value[key]
    }

    func set(_ data: Data, forKey key: String) throws {
      if let writeError {
        throw writeError
      }
      items.withValue { $0[key] = data }
    }

    func deleteItem(forKey key: String) throws {
      if let deleteError {
        throw deleteError
      }
      items.withValue { $0[key] = nil }
    }
  }
#endif
