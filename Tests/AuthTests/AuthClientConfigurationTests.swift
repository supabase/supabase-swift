//
//  AuthClientConfigurationTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthClientConfigurationTests {
  private let url = URL(string: "http://localhost:54321/auth/v1")!

  @Test
  func defaultsMatchTheDocumentedValues() {
    let configuration = AuthClient.Configuration(url: url, storageKey: "key")

    #expect(configuration.url == url)
    #expect(configuration.storageKey == "key")
    #expect(configuration.headers.isEmpty)
    #expect(configuration.redirectTo == nil)
    #expect(configuration.autoRefresh == .automatic)
    #expect(configuration.observesAppLifecycle)
    #expect(configuration.initialRefreshTimeout == .seconds(5))
    #expect(configuration.retryEnabled)
  }

  @Test
  func propertiesAreMutableAfterInit() {
    var configuration = AuthClient.Configuration(url: url, storageKey: "key")
    let redirect = URL(string: "app://login")!

    configuration.redirectTo = redirect
    configuration.autoRefresh = .manual
    configuration.headers[HTTPField.Name("X-Test")!] = "1"

    #expect(configuration.redirectTo == redirect)
    #expect(configuration.autoRefresh == .manual)
    #expect(configuration.headers[HTTPField.Name("X-Test")!] == "1")
  }

  @Test
  func nowDefaultsToTheSystemClock() {
    let configuration = AuthClient.Configuration(url: url, storageKey: "key")

    #expect(abs(configuration.now().timeIntervalSinceNow) < 5)
  }

  @Test
  func platformDefaultStoragePersists() {
    let configuration = AuthClient.Configuration(url: url, storageKey: "key")

    #if canImport(Security)
      #expect(configuration.storage is KeychainStorage)
    #else
      #expect(configuration.storage is InMemoryAuthStorage)
    #endif
  }

  @Test
  func configuredStorageIsTheOneTheClientWritesTo() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.save(
      PersistedSessionCodec.encode(Session.valid), key: "custom-key")
    let configuration = AuthClient.Configuration(
      url: url,
      storageKey: "custom-key",
      storage: storage)

    let sut = AuthClient(configuration: configuration)
    await sut.initialization()

    #expect(sut.currentSession == .valid)
  }

  @Test
  func loggerIsTaggedWithSystemMetadataByTheClient() {
    let configuration = AuthClient.Configuration(
      url: url,
      storageKey: "key",
      storage: InMemoryAuthStorage(),
      logger: Logging.Logger(label: "test")
    )

    let sut = AuthClient(configuration: configuration)
    let dependenciesLogger = sut.dependencies.logger

    #expect(dependenciesLogger[metadataKey: "system"] == "auth")
    #expect(dependenciesLogger[metadataKey: "client_id"] != nil)
  }

  @Test(arguments: [(true, 3), (false, 1)])
  func retryEnabledControlsWhetherAGetIsRetried(retryEnabled: Bool, attempts: Int) async {
    let requests = LockIsolated(0)
    var configuration = AuthClient.Configuration(
      url: url,
      storageKey: uniqueStorageKey(),
      storage: InMemoryAuthStorage(),
      http: .init(
        transport: ClosureTransport { _, _ in
          requests.withValue { $0 += 1 }
          return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil)
        }),
      clock: ImmediateClock()
    )
    configuration.retryEnabled = retryEnabled
    let sut = AuthClient(configuration: configuration)

    _ = try? await sut.user(jwt: "token")

    #expect(requests.value == attempts)
  }

  @Test
  func requestsCarryTheClientInfoHeaderAndTheConfiguredHeaders() async throws {
    let requests = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    var configuration = AuthClient.Configuration(
      url: url,
      storageKey: uniqueStorageKey(),
      storage: InMemoryAuthStorage(),
      http: .init(
        transport: ClosureTransport { request, _ in
          requests.withValue { $0.append(request) }
          return (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("{}".utf8)))
        })
    )
    configuration.headers[HTTPField.Name("apikey")!] = "publishable"
    let sut = AuthClient(configuration: configuration)

    _ = try? await sut.user(jwt: "token")

    let request = try #require(requests.value.first)
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "publishable")
    #expect(request.headerFields[HTTPField.Name("X-Client-Info")!] == "auth-swift/\(version)")
  }

  @Test
  func aConfiguredClientInfoHeaderWinsOverTheDefault() async throws {
    let requests = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    var configuration = AuthClient.Configuration(
      url: url,
      storageKey: uniqueStorageKey(),
      storage: InMemoryAuthStorage(),
      http: .init(
        transport: ClosureTransport { request, _ in
          requests.withValue { $0.append(request) }
          return (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("{}".utf8)))
        })
    )
    configuration.headers[HTTPField.Name("X-Client-Info")!] = "my-wrapper/1.0"
    let sut = AuthClient(configuration: configuration)

    _ = try? await sut.user(jwt: "token")

    let request = try #require(requests.value.first)
    #expect(request.headerFields[HTTPField.Name("X-Client-Info")!] == "my-wrapper/1.0")
  }

  @Test
  func loggerSetAfterInitRedactsSecretsBeforeTheCallersHandlerSeesThem() {
    let recorder = LogRecorder()
    var configuration = AuthClient.Configuration(
      url: URL(string: "http://localhost")!,
      storageKey: "key",
      storage: InMemoryAuthStorage()
    )
    configuration.logger = recorder.makeLogger()
    let sut = AuthClient(configuration: configuration)

    sut.configuration.logger.warning("refresh failed: refresh_token=r-secret-1")

    #expect(recorder.entries == ["refresh failed: refresh_token=<redacted> system=auth"])
  }
}
