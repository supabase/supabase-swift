import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@_spi(Testing) @testable import Auth
@testable import Functions
@_spi(Testing) @testable import PostgREST
@_spi(Testing) @testable import Realtime
@_spi(Testing) @testable import Storage
@_spi(Testing) @testable import Supabase

/// Every sub-client uses the global `http`, `logger` and `clock`, and runs the global middlewares
/// before the SDK's. A middleware or a log handler that branches on the module covers what the
/// per-module settings did.
@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientGlobalSettingsTests {
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

  // MARK: - Global settings reach every sub-client

  @Test
  func everySubClientUsesTheGlobalSettings() throws {
    let globalClock = TestClock<Duration>()
    let client = try makeClient {
      $0.global = .init(
        http: .init(transport: RecordingTransport(), timeout: .seconds(30)),
        logger: Logging.Logger(label: "global")
      )
      $0.global.clock = globalClock
    }

    let rest = client.rest.configuration
    #expect(rest.http.transport is RecordingTransport)
    #expect(rest.http.timeout == .seconds(30))
    #expect(rest.logger.label == "global")
    #expect(rest.clock as AnyObject === globalClock)

    let storage = client.storage.configuration
    #expect(storage.http.transport is RecordingTransport)
    #expect(storage.http.timeout == .seconds(30))
    #expect(storage.logger.label == "global")
    #expect(storage.clock as AnyObject === globalClock)

    let realtime = client.realtime.configuration
    #expect(realtime.http.transport is RecordingTransport)
    #expect(realtime.http.timeout == .seconds(30))
    #expect(realtime.logger.label == "global")
    #expect(realtime.clock as AnyObject === globalClock)

    let functions = client.functions.configuration
    #expect(functions.http.transport is RecordingTransport)
    #expect(functions.http.timeout == .seconds(30))
    #expect(functions.logger.label == "global")
  }

  @Test
  func realtimeTransportKeepsTheGlobalAndSDKMiddlewares() throws {
    let client = try makeClient {
      $0.global = .init(
        http: .init(middlewares: [HeaderMiddleware(name: "x-order", value: "global")]))
    }

    let middlewares = client.realtime.configuration.http.middlewares
    #expect(middlewares.count == 2)
    #expect((middlewares.first as? HeaderMiddleware)?.value == "global")
    #expect(middlewares.last is TraceContextMiddleware)
  }

  // MARK: - Replacement for a per-module `http`

  @Test
  func aPathBranchingMiddlewareSeesOnlyTheRequestsOfOneModule() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { _ in true }) { _, _ in (HTTPResponse(status: .ok), Data("[]".utf8)) }
    let storageOnly = RecordingMiddleware()
    let client = try makeClient {
      $0.global.http = .init(
        transport: transport,
        middlewares: [OnlyForPath(prefix: "/storage/v1/", inner: storageOnly)]
      )
    }

    _ = try await client.from("todos").select().execute()
    _ = try await client.storage.listBuckets()
    _ = try await client.functions.invoke("hello")

    #expect(transport.requests.count == 3)
    #expect(storageOnly.paths == ["/storage/v1/bucket"])
  }

  @Test
  func aPathBranchingTransportSendsOneModuleElsewhere() async throws {
    let storageTransport = RecordingTransport()
    storageTransport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .ok), Data("[]".utf8))
    }
    let otherTransport = RecordingTransport()
    otherTransport.respond(when: { _ in true }) { _, _ in
      (HTTPResponse(status: .ok), Data("[]".utf8))
    }
    let client = try makeClient {
      $0.global.http.transport = RoutingTransport(storage: storageTransport, other: otherTransport)
    }

    _ = try await client.from("todos").select().execute()
    _ = try await client.storage.listBuckets()

    #expect(storageTransport.requests.map(\.head.path) == ["/storage/v1/bucket"])
    #expect(otherTransport.requests.map(\.head.path) == ["/rest/v1/todos?select=%2A"])
  }

  // MARK: - Replacement for a per-module `logger`

  @Test
  func aSystemFilterKeepsTheLogsOfOneModule() throws {
    let lines = LockIsolated<[String]>([])
    let client = try makeClient {
      $0.global.logger = Logging.Logger(label: "io.supabase") { _ in
        SystemFilter(system: "storage", base: LineHandler(lines: lines))
      }
      $0.global.logger.logLevel = .trace
    }

    client.rest.configuration.logger.info("from postgrest")
    client.storage.configuration.logger.info("from storage")

    #expect(lines.value == ["from storage"])
  }

  // MARK: - Realtime headers

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

private struct OnlyForPath: ClientMiddleware {
  let prefix: String
  let inner: any ClientMiddleware

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    next:
      nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws -> (
        HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard request.path?.hasPrefix(prefix) == true else {
      return try await next(request, body)
    }
    return try await inner.intercept(request, body: body, next: next)
  }
}

private final class RecordingMiddleware: ClientMiddleware {
  private let recorded = LockIsolated<[String]>([])

  var paths: [String] { recorded.value }

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    next:
      nonisolated(nonsending) @Sendable (HTTPRequest, HTTPBody?) async throws -> (
        HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPResponse, HTTPBody?) {
    recorded.withValue { $0.append(request.path ?? "") }
    return try await next(request, body)
  }
}

private struct RoutingTransport: ClientTransport {
  let storage: any ClientTransport
  let other: any ClientTransport

  func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
    if request.path?.hasPrefix("/storage/v1/") == true {
      return try await storage.send(request, body: body)
    }
    return try await other.send(request, body: body)
  }
}

private struct SystemFilter: LogHandler {
  let system: String
  var base: any LogHandler

  var logLevel: Logging.Logger.Level {
    get { base.logLevel }
    set { base.logLevel = newValue }
  }

  var metadata: Logging.Logger.Metadata {
    get { base.metadata }
    set { base.metadata = newValue }
  }

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { base[metadataKey: key] }
    set { base[metadataKey: key] = newValue }
  }

  func log(event: LogEvent) {
    guard (event.metadata?["system"] ?? base.metadata["system"]) == .string(system) else { return }
    base.log(event: event)
  }
}

private struct LineHandler: LogHandler {
  let lines: LockIsolated<[String]>
  var logLevel: Logging.Logger.Level = .trace
  var metadata: Logging.Logger.Metadata = [:]

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    lines.withValue { $0.append(event.message.description) }
  }
}
