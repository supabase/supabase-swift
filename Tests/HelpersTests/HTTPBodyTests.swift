//
//  HTTPBodyTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 09/09/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import Helpers

@Suite
struct HTTPBodyTests {
  @Test
  func dataBodyIsKnownLengthAndReiterable() async throws {
    let body = HTTPBody(Data("hello".utf8))
    #expect(body.length == .known(5))
    #expect(body.iterationBehavior == .multiple)
    #expect(try await Data(collecting: body, upTo: 100) == Data("hello".utf8))
    #expect(try await Data(collecting: body, upTo: 100) == Data("hello".utf8))
  }

  @Test
  func singleIterationBodyThrowsOnSecondPass() async throws {
    let chunks = AsyncStream<ArraySlice<UInt8>> { continuation in
      continuation.yield(ArraySlice("ab".utf8))
      continuation.yield(ArraySlice("cd".utf8))
      continuation.finish()
    }
    let body = HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
    #expect(try await Data(collecting: body, upTo: 100) == Data("abcd".utf8))
    await #expect(throws: HTTPBodyAlreadyConsumedError.self) {
      _ = try await Data(collecting: body, upTo: 100)
    }
  }

  @Test
  func collectingPastTheCapThrows() async throws {
    let body = HTTPBody(Data(repeating: 0, count: 10))
    await #expect(throws: HTTPBodyTooLargeError.self) {
      _ = try await Data(collecting: body, upTo: 9)
    }
  }

  @Test
  func fileBodyReopensTheFileOnEveryIteration() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("file contents".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let body = try HTTPBody(fileURL: url)
    #expect(body.length == .known(13))
    #expect(body.iterationBehavior == .multiple)
    #expect(try await Data(collecting: body, upTo: 100) == Data("file contents".utf8))
    #expect(try await Data(collecting: body, upTo: 100) == Data("file contents".utf8))
  }

  @Test
  func writeToFileRoundTrips() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }

    try await HTTPBody(Data("on disk".utf8)).write(to: url)
    #expect(try Data(contentsOf: url) == Data("on disk".utf8))
  }

  @Test
  func reportingProgressReportsCumulativeBytes() async throws {
    let chunks = AsyncStream<ArraySlice<UInt8>> { continuation in
      continuation.yield(ArraySlice([1, 2, 3]))
      continuation.yield(ArraySlice([4, 5]))
      continuation.finish()
    }
    let seen = LockIsolated<[Int64]>([])
    let body = HTTPBody(chunks, length: .known(5), iterationBehavior: .single)
      .reportingProgress { bytes in seen.withValue { $0.append(bytes) } }
    _ = try await Data(collecting: body, upTo: 100)
    #expect(seen.value == [3, 5])
    #expect(body.length == .known(5))
  }
}
