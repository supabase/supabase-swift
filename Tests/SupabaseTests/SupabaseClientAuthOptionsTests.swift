import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@_spi(Testing) @testable import Auth
@_spi(Testing) @testable import Supabase

@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientAuthOptionsTests {
  private let url = URL(string: "https://project-ref.supabase.co")!

  private func makeClient(
    auth: SupabaseClient.Configuration.Auth,
    global: SupabaseClient.Configuration.Global = .init()
  ) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: url,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(auth: auth, global: global)
    )
  }

  @Test
  func redirectToForwardsToTheAuthClient() throws {
    let redirect = URL(string: "com.example.app://callback")!
    let client = try makeClient(
      auth: .init(storage: InMemoryAuthStorage(), redirectTo: redirect, autoRefresh: .manual)
    )

    #expect(client.auth.configuration.redirectTo == redirect)
  }

  @Test(arguments: [true, false])
  func acceptsImplicitTokensForwardsToTheAuthClient(accepts: Bool) throws {
    let client = try makeClient(
      auth: .init(
        storage: InMemoryAuthStorage(), acceptsImplicitTokens: accepts, autoRefresh: .manual)
    )

    #expect(client.auth.configuration.acceptsImplicitTokens == accepts)
  }

  @Test
  func implicitTokensAreRefusedByDefault() throws {
    let client = try makeClient(auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual))

    #expect(client.auth.configuration.acceptsImplicitTokens == false)
  }

  @Test
  func authUsesTheGlobalClock() throws {
    let globalClock = TestClock<Duration>()
    var global = SupabaseClient.Configuration.Global()
    global.clock = globalClock
    let client = try makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: global
    )

    #expect(client.auth.configuration.clock as AnyObject === globalClock)
  }

  @Test
  func authUsesTheGlobalLoggerTaggedWithItsSystem() throws {
    let client = try makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: .init(logger: Logging.Logger(label: "global"))
    )

    #expect(client.auth.configuration.logger.label == "global")
    #expect(client.auth.configuration.logger[metadataKey: "system"] == "auth")
  }

  @Test
  func authMiddlewaresAreTheGlobalOnes() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .badRequest), Data("{}".utf8))
    }
    let client = try makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: .init(
        http: .init(
          transport: transport, middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
    )

    _ = try? await client.auth.signIn(email: "a@b.c", password: "x")

    let request = try #require(
      transport.requests.first { $0.head.path?.hasPrefix("/auth/v1/token") == true })
    #expect(request.head.headerFields[HTTPField.Name("x-order")!] == "global")
  }

  @Test
  func authUsesTheGlobalTimeout() throws {
    let client = try makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: .init(http: .init(timeout: .seconds(30)))
    )

    #expect(client.auth.configuration.http.timeout == .seconds(30))
  }
}
