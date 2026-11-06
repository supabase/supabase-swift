#if !canImport(Darwin)
  extension AuthPlatform {
    static var defaultStorage: any AuthStorage { InMemoryAuthStorage() }
  }
#endif
