import Auth
import Foundation
import Testing

/// Imports `Auth` without `@testable`, so the test fails to compile if `configuration` is not
/// public.
@Suite
struct AuthClientPublicConfigurationTests {
  @Test
  func clientExposesTheConfigurationItWasCreatedWith() {
    let url = URL(string: "http://localhost:54321/auth/v1")!
    let client = AuthClient(
      configuration: .init(
        url: url,
        storageKey: "public-configuration",
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual,
        initialRefreshTimeout: .seconds(2)
      )
    )

    #expect(client.configuration.url == url)
    #expect(client.configuration.storageKey == "public-configuration")
    #expect(client.configuration.initialRefreshTimeout == .seconds(2))
  }
}
