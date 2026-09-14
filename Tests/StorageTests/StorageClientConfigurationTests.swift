import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageClientConfigurationTests {
  let url = URL(string: "http://localhost")!

  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = StorageClientConfiguration(
      url: url,
      headers: [:],
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "storage")
  }

  @Test
  func retryPolicyRetriesTransientFailures() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient(retryPolicy: RetryPolicy(baseDelay: .zero)) {
      attempts.withValue { $0 += 1 }
      if attempts.value < 2 {
        return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil)
      }
      return (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
    }

    _ = try await client.listBuckets()
    #expect(attempts.value == 2)
  }

  @Test
  func disabledRetryPolicyMakesOneAttempt() async {
    let attempts = LockIsolated(0)
    let client = makeClient(retryPolicy: .disabled) {
      attempts.withValue { $0 += 1 }
      return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil)
    }

    await #expect(throws: StorageError.self) { try await client.listBuckets() }
    #expect(attempts.value == 1)
  }

  private func makeClient(
    retryPolicy: RetryPolicy,
    transport: @escaping @Sendable () -> (HTTPTypes.HTTPResponse, HTTPBody?)
  ) -> SupabaseStorageClient {
    SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: [:],
        http: .init(transport: ClosureTransport { _, _ in transport() }),
        retryPolicy: retryPolicy
      )
    )
  }
}
