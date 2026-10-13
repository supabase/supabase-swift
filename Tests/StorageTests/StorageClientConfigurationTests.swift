import ConcurrencyExtras
import Foundation
import Helpers
import HTTPTypes
import Logging
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageClientConfigurationTests {
  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = StorageClientConfiguration(
      url: URL(string: "http://localhost")!,
      headers: [:],
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "storage")
  }

  /// Records the head of every request and answers an empty bucket list.
  private func makeSUT(
    headers: HTTPFields,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    requests: LockIsolated<[HTTPRequest]>
  ) -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: headers,
        http: .init(
          transport: ClosureTransport { request, _ in
            requests.withValue { $0.append(request) }
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data("[]".utf8))
            )
          },
          middlewares: accessToken.map { [AccessTokenMiddleware(getAccessToken: $0)] } ?? []
        )
      ))
  }

  @Test
  func accessTokenMiddlewareSendsTheBearer() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: [:], accessToken: { "token-1" }, requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.authorization] == "Bearer token-1")
  }

  @Test
  func accessTokenMiddlewareResolvesPerRequest() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let counter = LockIsolated(0)
    let storage = makeSUT(
      headers: [:],
      accessToken: {
        counter.withValue {
          $0 += 1; return "token-\($0)"
        }
      },
      requests: requests)

    _ = try await storage.listBuckets()
    _ = try await storage.listBuckets()

    #expect(
      requests.value.map { $0.headerFields[.authorization] } == [
        "Bearer token-1", "Bearer token-2",
      ])
  }

  @Test
  func nilTokenSendsNoAuthorization() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: [:], accessToken: { nil }, requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.authorization] == nil)
  }

  /// The configured headers are merged before the middleware chain runs, so a static
  /// `Authorization` wins over the token the middleware would set.
  @Test
  func staticAuthorizationHeaderWinsOverAccessTokenMiddleware() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(
      headers: [.authorization: "Bearer static"], accessToken: { "token-1" }, requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.authorization] == "Bearer static")
  }

  @Test
  func xClientInfoIsMatchedCaseInsensitively() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: [.init("x-client-info")!: "my-app/1.0"], requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.xClientInfo] == "my-app/1.0")
  }

  @Test
  func setHeaderMergesWithoutRebuildingTheClient() async throws {
    let storage = StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "https://project.supabase.co/storage/v1")!,
        headers: [.xClientInfo: "custom/1"],
        usesNewHostname: true
      )
    ).setHeader(name: .init("X-Custom")!, value: "value")

    #expect(
      storage.configuration.url.absoluteString == "https://project.storage.supabase.co/storage/v1")
    #expect(storage.configuration.headers[.xClientInfo] == "custom/1")
    #expect(storage.configuration.headers[.init("x-custom")!] == "value")
  }
}
