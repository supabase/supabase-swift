import ConcurrencyExtras
import Foundation
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
    headers: [String: String],
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
          }),
        accessToken: accessToken
      ))
  }

  @Test
  func accessTokenIsSentAsBearer() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: [:], accessToken: { "token-1" }, requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.authorization] == "Bearer token-1")
  }

  @Test
  func accessTokenIsResolvedPerRequest() async throws {
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

  /// A static `Authorization` is the legacy way to pass a key; it wins so existing callers keep
  /// the header they set. (Passing both at construction also reports an issue, which Swift
  /// Testing under an XCTest bundle cannot observe without crashing, so the header is merged in
  /// afterwards here.)
  @Test
  func staticAuthorizationHeaderWinsOverAccessToken() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: [:], accessToken: { "token-1" }, requests: requests)
      .setHeader("Bearer static", forKey: "Authorization")

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.authorization] == "Bearer static")
  }

  @Test
  func xClientInfoIsMatchedCaseInsensitively() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let storage = makeSUT(headers: ["x-client-info": "my-app/1.0"], requests: requests)

    _ = try await storage.listBuckets()

    #expect(requests.value.first?.headerFields[.xClientInfo] == "my-app/1.0")
  }

  @Test
  func setHeaderMergesWithoutRebuildingTheClient() async throws {
    let storage = StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "https://project.supabase.co/storage/v1")!,
        headers: ["X-Client-Info": "custom/1"],
        usesNewHostname: true
      )
    ).setHeader("value", forKey: "X-Custom")

    #expect(
      storage.configuration.url.absoluteString == "https://project.storage.supabase.co/storage/v1")
    #expect(storage.configuration.headers["X-Client-Info"] == "custom/1")
    #expect(storage.configuration.headers["x-custom"] == "value")
  }
}
