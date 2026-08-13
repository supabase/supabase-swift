#if !os(Windows) && !os(Linux) && !os(Android)
  import ConcurrencyExtras
  import Foundation
  import Testing

  @testable import Auth

  @Suite
  struct KeychainLocalStorageTests {
    @Test
    func primaryConfigurationUsesBundleIdentifier() {
      let configuration = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: "com.example.app",
        accessGroup: nil,
        useDataProtectionKeychain: false
      )
      #expect(configuration.service == "com.example.app")
    }

    @Test
    func primaryConfigurationFallsBackToLegacyService() {
      let configuration = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: nil,
        accessGroup: nil,
        useDataProtectionKeychain: false
      )
      #expect(configuration.service == "supabase.gotrue.swift")
    }

    @Test
    func legacyConfigurationsContainsLegacyService() {
      let primary = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: "com.example.app",
        accessGroup: nil,
        useDataProtectionKeychain: false
      )
      let legacy = KeychainLocalStorage.legacyConfigurations(primary: primary)

      #expect(
        legacy == [
          KeychainConfiguration(
            service: "supabase.gotrue.swift",
            accessGroup: nil,
            useDataProtectionKeychain: false
          )
        ]
      )
    }

    @Test
    func legacyConfigurationsWithDataProtectionAlsoProbesFileBasedPrimary() {
      let primary = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: "com.example.app",
        accessGroup: "group",
        useDataProtectionKeychain: true
      )
      let legacy = KeychainLocalStorage.legacyConfigurations(primary: primary)

      #expect(
        legacy == [
          KeychainConfiguration(
            service: "supabase.gotrue.swift",
            accessGroup: "group",
            useDataProtectionKeychain: false
          ),
          KeychainConfiguration(
            service: "com.example.app",
            accessGroup: "group",
            useDataProtectionKeychain: false
          ),
        ]
      )
    }

    @Test
    func legacyConfigurationsExcludesPrimary() {
      // No bundle identifier means the primary already is the legacy location.
      let primary = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: nil,
        accessGroup: nil,
        useDataProtectionKeychain: false
      )
      #expect(KeychainLocalStorage.legacyConfigurations(primary: primary).isEmpty)
    }

    @Test
    func legacyConfigurationsDeduplicates() {
      // No bundle identifier plus data protection would otherwise yield the same entry twice.
      let primary = KeychainLocalStorage.primaryConfiguration(
        bundleIdentifier: nil,
        accessGroup: nil,
        useDataProtectionKeychain: true
      )
      #expect(KeychainLocalStorage.legacyConfigurations(primary: primary).count == 1)
    }

    @Test
    func explicitServiceDoesNotMigrate() {
      let storage = KeychainLocalStorage(service: "custom")
      #expect(storage.legacyKeychains.isEmpty)
    }

    @Test
    func retrieveMigratesFromLegacyLocation() throws {
      let value = Data("session".utf8)
      let primary = FakeKeychain()
      let legacy = FakeKeychain(items: ["key": value])
      let storage = KeychainLocalStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try storage.retrieve(key: "key") == value)
      #expect(primary.items.value["key"] == value)
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func retrievePrefersPrimaryAndLeavesLegacyUntouched() throws {
      let primaryValue = Data("new".utf8)
      let legacyValue = Data("old".utf8)
      let primary = FakeKeychain(items: ["key": primaryValue])
      let legacy = FakeKeychain(items: ["key": legacyValue])
      let storage = KeychainLocalStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try storage.retrieve(key: "key") == primaryValue)
      #expect(legacy.items.value["key"] == legacyValue)
    }

    @Test
    func retrieveProbesLegacyLocationsInOrder() throws {
      let first = FakeKeychain(items: ["key": Data("first".utf8)])
      let second = FakeKeychain(items: ["key": Data("second".utf8)])
      let primary = FakeKeychain()
      let storage = KeychainLocalStorage(
        keychain: primary,
        legacyKeychains: [first, second]
      )

      #expect(try storage.retrieve(key: "key") == Data("first".utf8))
      #expect(primary.items.value["key"] == Data("first".utf8))
      #expect(first.items.value["key"] == nil)
      #expect(second.items.value["key"] == Data("second".utf8))
    }

    @Test
    func retrieveMissingEverywhereReturnsNil() throws {
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(),
        legacyKeychains: [FakeKeychain()]
      )
      #expect(try storage.retrieve(key: "key") == nil)
    }

    @Test
    func retrievePropagatesLegacyProbeFailure() {
      struct ProbeFailure: Error {}
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(),
        legacyKeychains: [FakeKeychain(readError: ProbeFailure())]
      )

      // A genuine legacy failure must surface rather than read as "no session" — an absent
      // item already returns nil, so a throw here is never just a miss.
      #expect(throws: ProbeFailure.self) {
        try storage.retrieve(key: "key")
      }
    }

    @Test
    func retrievePropagatesPrimaryFailure() {
      struct PrimaryFailure: Error {}
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(readError: PrimaryFailure()),
        legacyKeychains: []
      )
      #expect(throws: PrimaryFailure.self) {
        try storage.retrieve(key: "key")
      }
    }

    @Test
    func removeClearsPrimaryAndLegacyLocations() throws {
      let primary = FakeKeychain(items: ["key": Data()])
      let legacy = FakeKeychain(items: ["key": Data()])
      let storage = KeychainLocalStorage(keychain: primary, legacyKeychains: [legacy])

      try storage.remove(key: "key")

      #expect(primary.items.value["key"] == nil)
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func removeClearsLegacyLocationsEvenWhenPrimaryDeleteFails() {
      struct DeleteFailure: Error {}
      let primary = FakeKeychain(items: ["key": Data()], deleteError: DeleteFailure())
      let legacy = FakeKeychain(items: ["key": Data()])
      let storage = KeychainLocalStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(throws: DeleteFailure.self) {
        try storage.remove(key: "key")
      }
      #expect(legacy.items.value["key"] == nil)
    }

    @Test
    func retrieveReturnsLegacyValueAndKeepsItWhenPrimaryWriteFails() throws {
      struct WriteFailure: Error {}
      let legacyValue = Data("session".utf8)
      let primary = FakeKeychain(writeError: WriteFailure())
      let legacy = FakeKeychain(items: ["key": legacyValue])
      let storage = KeychainLocalStorage(keychain: primary, legacyKeychains: [legacy])

      #expect(try storage.retrieve(key: "key") == legacyValue)
      #expect(legacy.items.value["key"] == legacyValue)
      #expect(primary.items.value["key"] == nil)
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
