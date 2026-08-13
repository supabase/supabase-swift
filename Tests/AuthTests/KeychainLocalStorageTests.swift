#if !os(Windows) && !os(Linux) && !os(Android)
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
  }
#endif
