#if canImport(Darwin)
  extension AuthPlatform {
    /// Keeps the macOS file-based Keychain, so an unsigned Mac app and a test bundle still work.
    static var defaultStorage: any AuthStorage {
      KeychainStorage(useDataProtectionKeychain: false)
    }
  }
#endif
