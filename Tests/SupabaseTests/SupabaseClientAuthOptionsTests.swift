import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Auth
@testable import Supabase

@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientAuthOptionsTests {
  private let url = URL(string: "https://project-ref.supabase.co")!

  private func makeClient(
    auth: SupabaseClient.Configuration.Auth,
    global: SupabaseClient.Configuration.Global = .init()
  ) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: url,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(auth: auth, global: global)
    )
  }

  @Test
  func authClockOverridesTheGlobalClock() {
    let authClock = TestClock<Duration>()
    let globalClock = TestClock<Duration>()
    let client = makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual, clock: authClock),
      global: .init(clock: globalClock)
    )

    #expect(client.auth.configuration.clock as AnyObject === authClock)
    #expect(client.clock as AnyObject === globalClock)
  }

  @Test
  func redirectToForwardsToTheAuthClient() {
    let redirect = URL(string: "com.example.app://callback")!
    let client = makeClient(
      auth: .init(storage: InMemoryAuthStorage(), redirectTo: redirect, autoRefresh: .manual)
    )

    #expect(client.auth.configuration.redirectTo == redirect)
  }

  @Test
  func authClockFallsBackToTheGlobalClock() {
    let globalClock = TestClock<Duration>()
    let client = makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: .init(clock: globalClock)
    )

    #expect(client.auth.configuration.clock as AnyObject === globalClock)
  }

  @Test
  func authLoggerOverridesTheGlobalLogger() {
    let client = makeClient(
      auth: .init(
        storage: InMemoryAuthStorage(), autoRefresh: .manual,
        logger: Logging.Logger(label: "auth-logger")),
      global: .init(logger: Logging.Logger(label: "global"))
    )

    #expect(client.auth.configuration.logger.label == "auth-logger")
    #expect(client.auth.configuration.logger[metadataKey: "system"] == "auth")
  }

  @Test
  func authLoggerFallsBackToTheGlobalLogger() {
    let client = makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
      global: .init(logger: Logging.Logger(label: "global"))
    )

    #expect(client.auth.configuration.logger.label == "global")
  }

  @Test
  func authHTTPOverridesTheGlobalTransportForAuthOnly() async throws {
    let globalTransport = RecordingTransport()
    let authTransport = RecordingTransport()
    authTransport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .badRequest), Data("{}".utf8))
    }
    globalTransport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .ok), Data("[]".utf8))
    }
    let client = makeClient(
      auth: .init(
        storage: InMemoryAuthStorage(), autoRefresh: .manual,
        http: .init(transport: authTransport)),
      global: .init(http: .init(transport: globalTransport))
    )

    _ = try? await client.auth.signIn(email: "a@b.c", password: "x")
    _ = try? await client.from("todos").select().execute()

    #expect(authTransport.requests.contains { $0.head.path?.hasPrefix("/auth/v1/") == true })
    #expect(!globalTransport.requests.contains { $0.head.path?.hasPrefix("/auth/v1/") == true })
    #expect(globalTransport.requests.contains { $0.head.path?.hasPrefix("/rest/v1/") == true })
    #expect(!authTransport.requests.contains { $0.head.path?.hasPrefix("/rest/v1/") == true })
  }

  @Test
  func authHTTPMiddlewaresRunAfterTheGlobalOnes() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .badRequest), Data("{}".utf8))
    }
    let client = makeClient(
      auth: .init(
        storage: InMemoryAuthStorage(), autoRefresh: .manual,
        http: .init(middlewares: [HeaderMiddleware(name: "x-order", value: "auth")])),
      global: .init(
        http: .init(
          transport: transport, middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
    )

    _ = try? await client.auth.signIn(email: "a@b.c", password: "x")

    let request = try #require(
      transport.requests.first { $0.head.path?.hasPrefix("/auth/v1/token") == true })
    #expect(request.head.headerFields[HTTPField.Name("x-order")!] == "global,auth")
  }

  @Test
  func authHTTPTimeoutFallsBackToTheGlobalTimeout() {
    let client = makeClient(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual, http: .init()),
      global: .init(http: .init(timeout: .seconds(30)))
    )

    #expect(client.auth.configuration.http.timeout == .seconds(30))
  }

  @Test
  func authHTTPTimeoutOverridesTheGlobalTimeout() {
    let client = makeClient(
      auth: .init(
        storage: InMemoryAuthStorage(), autoRefresh: .manual, http: .init(timeout: .seconds(7))),
      global: .init(http: .init(timeout: .seconds(30)))
    )

    #expect(client.auth.configuration.http.timeout == .seconds(7))
  }
}

private struct HeaderMiddleware: ClientMiddleware {
  let name: String
  let value: String

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var request = request
    let field = HTTPField.Name(name)!
    request.headerFields[field] = [request.headerFields[field], value].compactMap { $0 }
      .joined(separator: ",")
    return try await next(request, body)
  }
}
