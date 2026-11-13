import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthConfigurationV3APITests {
  let redirect = URL(string: "myapp://callback")!

  @Test
  func redirectToIsSetByTheInitializer() {
    let configuration = AuthClient.Configuration(
      url: URL(string: "https://example.com")!, redirectToURL: redirect,
      localStorage: InMemoryLocalStorage())
    #expect(configuration.redirectTo == redirect)
  }

  @available(*, deprecated, message: "Compares with the deprecated v2 property.")
  @Test
  func redirectToAndRedirectToURLAreTheSameValue() {
    var configuration = AuthClient.Configuration(
      url: URL(string: "https://example.com")!, localStorage: InMemoryLocalStorage())
    #expect(configuration.redirectTo == nil)

    configuration.redirectTo = redirect
    #expect(configuration.redirectToURL == redirect)

    configuration.redirectToURL = nil
    #expect(configuration.redirectTo == nil)
  }

  @available(*, deprecated, message: "Compares with the deprecated v2 initializer.")
  @Test
  func clientInitializersBuildTheSameConfiguration() {
    let url = URL(string: "https://example.com")!
    let old = AuthClient(
      url: url, headers: ["apikey": "key"], redirectToURL: redirect, storageKey: "key",
      localStorage: InMemoryLocalStorage(), autoRefreshToken: false)
    let new = AuthClient(
      configuration: AuthClient.Configuration(
        url: url, headers: ["apikey": "key"], redirectToURL: redirect, storageKey: "key",
        localStorage: InMemoryLocalStorage(), autoRefreshToken: false))

    #expect(old.configuration.url == new.configuration.url)
    #expect(old.configuration.headers == new.configuration.headers)
    #expect(old.configuration.redirectTo == new.configuration.redirectTo)
    #expect(old.configuration.storageKey == new.configuration.storageKey)
    #expect(old.configuration.autoRefreshToken == new.configuration.autoRefreshToken)
  }
}
