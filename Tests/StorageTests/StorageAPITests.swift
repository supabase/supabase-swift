//
//  StorageAPITests.swift
//  Storage
//
//  Created by Guilherme Souza on 16/09/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageAPITests {
  @Test(arguments: [false, true])
  func throwsWhenTheURLHasNoHost(usesNewHostname: Bool) throws {
    let error = #expect(throws: StorageError.self) {
      try StorageClient(
        configuration: StorageClientConfiguration(
          url: URL(string: "project-ref")!,
          headers: [:],
          usesNewHostname: usesNewHostname
        )
      )
    }
    #expect(error?.kind == .invalidConfiguration)
  }

  private func makeSUT(retryEnabled: Bool = true) throws -> (
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
    return (try StorageClient(configuration: configuration), attempts)
  }

  @Test
  func listIsRetriedPerPolicy() async throws {
    let (storage, attempts) = try makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").list()
    }

    #expect(attempts.value.count == RetryPolicy.default.maxAttempts)
  }

  @Test
  func getIsRetriedPerPolicy() async throws {
    let (storage, attempts) = try makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.listBuckets()
    }

    #expect(attempts.value.count == RetryPolicy.default.maxAttempts)
  }

  @Test
  func uploadIsNeverRetried() async throws {
    let (storage, attempts) = try makeSUT()

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").upload(path: "file.txt", data: Data("x".utf8))
    }

    #expect(attempts.value.count == 1)
  }

  @Test
  func retryEnabledFalseDisablesRetries() async throws {
    let (storage, attempts) = try makeSUT(retryEnabled: false)

    await #expect(throws: StorageError.self) {
      _ = try await storage.from("bucket").list()
    }

    #expect(attempts.value.count == 1)
  }
}
