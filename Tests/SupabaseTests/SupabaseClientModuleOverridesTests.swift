import Clocks
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Auth
@testable import PostgREST
@testable import Realtime
@testable import Storage
@testable import Supabase

/// Every sub-client resolves `module ?? global` for `http`, `logger` and `clock`, and runs the
/// global middlewares, then the module's, then the SDK's.
@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientModuleOverridesTests {
  private let url = URL(string: "https://project-ref.supabase.co")!

  private func makeClient(
    _ configure: (inout SupabaseClient.Configuration) -> Void
  ) throws -> SupabaseClient {
    var configuration = SupabaseClient.Configuration(
      auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual)
    )
    configure(&configuration)
    return try SupabaseClient(
      supabaseURL: url,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: configuration
    )
  }

  // MARK: - Database

  @Test
  func databaseOverridesWinOverTheGlobalOnes() throws {
    let databaseClock = TestClock<Duration>()
    let databaseTransport = ClosureTransport { _, _ in throw URLError(.cancelled) }
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: RecordingTransport(), timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: TestClock<Duration>()
      )
      $0.database = .init(
        http: .init(transport: databaseTransport, timeout: .seconds(7)),
        logger: Logging.Logger(label: "database"),
        clock: databaseClock
      )
    }

    let configuration = client.rest.configuration
    #expect(configuration.http.transport is ClosureTransport)
    #expect(configuration.http.timeout == .seconds(7))
    #expect(configuration.logger.label == "database")
    #expect(configuration.clock as AnyObject === databaseClock)
  }

  @Test
  func databaseFallsBackToTheGlobalSettings() throws {
    let globalClock = TestClock<Duration>()
    let globalTransport = RecordingTransport()
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: globalTransport, timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: globalClock
      )
    }

    let configuration = client.rest.configuration
    #expect(configuration.http.transport is RecordingTransport)
    #expect(configuration.http.timeout == .seconds(30))
    #expect(configuration.logger.label == "global")
    #expect(configuration.clock as AnyObject === globalClock)
  }

  @Test
  func databaseMiddlewaresRunAfterTheGlobalOnes() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { _ in true }) { _, _ in (HTTPResponse(status: .ok), Data("[]".utf8)) }
    let client = try makeClient {
      $0.global = .init(
        http: .init(
          transport: transport, middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
      $0.database = .init(
        http: .init(middlewares: [HeaderMiddleware(name: "x-order", value: "database")]))
    }

    _ = try await client.from("todos").select().execute()

    let request = try #require(transport.requests.first)
    #expect(request.head.headerFields[HTTPField.Name("x-order")!] == "global,database")
    #expect(request.head.headerFields[.authorization] == "Bearer PUBLISHABLE_KEY")
  }

  // MARK: - Storage

  @Test
  func storageOverridesWinOverTheGlobalOnes() throws {
    let storageClock = TestClock<Duration>()
    let storageTransport = ClosureTransport { _, _ in throw URLError(.cancelled) }
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: RecordingTransport(), timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: TestClock<Duration>()
      )
      $0.storage = .init(
        http: .init(transport: storageTransport, timeout: .seconds(7)),
        logger: Logging.Logger(label: "storage"),
        clock: storageClock
      )
    }

    let configuration = client.storage.configuration
    #expect(configuration.http.transport is ClosureTransport)
    #expect(configuration.http.timeout == .seconds(7))
    #expect(configuration.logger.label == "storage")
    #expect(configuration.clock as AnyObject === storageClock)
  }

  @Test
  func storageFallsBackToTheGlobalSettings() throws {
    let globalClock = TestClock<Duration>()
    let globalTransport = RecordingTransport()
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: globalTransport, timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: globalClock
      )
    }

    let configuration = client.storage.configuration
    #expect(configuration.http.transport is RecordingTransport)
    #expect(configuration.http.timeout == .seconds(30))
    #expect(configuration.logger.label == "global")
    #expect(configuration.clock as AnyObject === globalClock)
  }

  @Test
  func storageMiddlewaresRunAfterTheGlobalOnes() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { _ in true }) { _, _ in (HTTPResponse(status: .ok), Data("[]".utf8)) }
    let client = try makeClient {
      $0.global = .init(
        http: .init(
          transport: transport, middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
      $0.storage = .init(
        http: .init(middlewares: [HeaderMiddleware(name: "x-order", value: "storage")]))
    }

    _ = try await client.storage.listBuckets()

    let request = try #require(transport.requests.first)
    #expect(request.head.headerFields[HTTPField.Name("x-order")!] == "global,storage")
    #expect(request.head.headerFields[.authorization] == "Bearer PUBLISHABLE_KEY")
  }

  // MARK: - Realtime

  @Test
  func realtimeTransportKeepsTheGlobalAndSDKMiddlewares() throws {
    let realtimeTransport = ClosureTransport { _, _ in throw URLError(.cancelled) }
    let client = try makeClient {
      $0.global = .init(
        http: .init(middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
      $0.realtime = .init(
        http: .init(
          transport: realtimeTransport,
          middlewares: [HeaderMiddleware(name: "x-order", value: "realtime")]))
    }

    let http = client.realtime.configuration.http
    #expect(http.transport is ClosureTransport)
    let middlewares = http.middlewares
    #expect(middlewares.count == 3)
    #expect((middlewares.first as? HeaderMiddleware)?.value == "global")
    #expect((middlewares.dropFirst().first as? HeaderMiddleware)?.value == "realtime")
    #expect(middlewares.last is TraceContextMiddleware)
  }

  @Test
  func realtimeOverridesWinOverTheGlobalOnes() throws {
    let realtimeClock = TestClock<Duration>()
    let client = try makeClient {
      $0.global = .init(
        http: .init(timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: TestClock<Duration>()
      )
      $0.realtime = .init(
        http: .init(timeout: .seconds(7)),
        logger: Logging.Logger(label: "realtime"),
        clock: realtimeClock
      )
    }

    let configuration = client.realtime.configuration
    #expect(configuration.http.timeout == .seconds(7))
    #expect(configuration.logger.label == "realtime")
    #expect(configuration.clock as AnyObject === realtimeClock)
  }

  @Test
  func realtimeFallsBackToTheGlobalSettings() throws {
    let globalClock = TestClock<Duration>()
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: RecordingTransport(), timeout: .seconds(30)),
        logger: Logging.Logger(label: "global"),
        clock: globalClock
      )
    }

    let configuration = client.realtime.configuration
    #expect(configuration.http.transport is RecordingTransport)
    #expect(configuration.http.timeout == .seconds(30))
    #expect(configuration.logger.label == "global")
    #expect(configuration.clock as AnyObject === globalClock)
  }

  @Test
  func realtimeHeadersWinOverTheGlobalHeaders() throws {
    let client = try makeClient {
      $0.global = .init(headers: [.custom: "global", .apikey: "global-key"])
      $0.realtime = .init(headers: [.custom: "realtime", .apikey: "realtime-key"])
    }

    let headers = client.realtime.configuration.headers
    #expect(headers[values: .custom] == ["realtime"])
    #expect(headers[values: .apikey] == ["realtime-key"])
  }

  @Test
  func realtimeHeadersFallBackToTheGlobalAndSDKHeaders() throws {
    let client = try makeClient {
      $0.global = .init(headers: [.custom: "global"])
    }

    let headers = client.realtime.configuration.headers
    #expect(headers[.custom] == "global")
    #expect(headers[.apikey] == "PUBLISHABLE_KEY")
    #expect(headers[.authorization] == "Bearer PUBLISHABLE_KEY")
  }
}

extension HTTPField.Name {
  fileprivate static let custom = HTTPField.Name("X-Custom")!
}
