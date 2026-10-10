//
//  StorageAPITests.swift
//  Storage
//
//  Created by Guilherme Souza on 16/09/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageAPITests {
  #if os(macOS) || os(Linux)
    /// `usesNewHostname` rewrites the host at construction, so a URL with no host is a programmer
    /// error the initializer traps on, rather than a `URLError` surfacing on the first request.
    @Test
    func newHostnameWithoutAHostTraps() async {
      await #expect(processExitsWith: .failure) {
        _ = StorageAPI(
          configuration: StorageClientConfiguration(
            url: URL(string: "project-ref")!,
            headers: [:],
            usesNewHostname: true
          )
        )
      }
    }
  #endif

  /// Answers every request with a 503 and records the path of each attempt.
  private func makeSUT(retryEnabled: Bool = true) -> (
    StorageClient, LockIsolated<[String]>
  ) {
    let attempts = LockIsolated<[String]>([])
    var configuration = StorageClientConfiguration(
      url: URL(string: "http://localhost:54321/storage/v1")!,
      headers: [:],
      http: .init(
        transport: ClosureTransport { request, _ in
          attempts.withValue { $0.append(request.path ?? "") }
          return (HTTPResponse(status: .serviceUnavailable), nil)
        }),
      retryEnabled: retryEnabled
    )
    configuration.clock = ImmediateClock()
    return (StorageClient(configuration: configuration), attempts)
  }

  @Test
  func listIsRetriedPerPolicy() async {
    let (storage, attempts) = makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").list()
    }

    #expect(attempts.value.count == RetryPolicy.default.maxAttempts)
  }

  @Test
  func getIsRetriedPerPolicy() async {
    let (storage, attempts) = makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.listBuckets()
    }

    #expect(attempts.value.count == RetryPolicy.default.maxAttempts)
  }

  @Test
  func uploadIsNeverRetried() async {
    let (storage, attempts) = makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").upload(path: "file.txt", data: Data("x".utf8))
    }

    #expect(attempts.value.count == 1)
  }

  @Test
  func retryEnabledFalseDisablesRetries() async {
    let (storage, attempts) = makeSUT(retryEnabled: false)

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").list()
    }

    #expect(attempts.value.count == 1)
  }
}

/// A clock whose sleeps return at once, so retry tests do not wait out the backoff.
private struct ImmediateClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: Duration { ContinuousClock().minimumResolution }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {}
}
