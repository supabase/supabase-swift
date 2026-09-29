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
  func dataBodyIsKnownLengthAndIteratesTwice() async throws {
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
  func chunkSequenceIsPulledOnlyWhenTheConsumerAsks() async throws {
    let pulls = LockIsolated(0)
    let chunks = AsyncStream<ArraySlice<UInt8>> {
      let count = pulls.withValue { value -> Int in
        value += 1
        return value
      }
      return count <= 5 ? ArraySlice([UInt8(count)]) : nil
    }
    let body = HTTPBody(chunks, length: .unknown, iterationBehavior: .single)

    var iterator = body.makeAsyncIterator()
    #expect(try await iterator.next() == [1])
    try await Task.sleep(for: .milliseconds(50))

    // One pull per `next()`: nothing reads ahead into a buffer the consumer has not asked for.
    #expect(pulls.value == 1)
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
  func fileBodyYieldsChunksAsItReads() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let size = 64 * 1024 + 7
    try Data(repeating: 9, count: size).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let body = try HTTPBody(fileURL: url)
    var iterator = body.makeAsyncIterator()
    let first = try #require(try await iterator.next())
    #expect(first.count == 64 * 1024)

    var total = first.count
    while let chunk = try await iterator.next() { total += chunk.count }
    #expect(total == size)
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

  @Test
  func reportingProgressKeepsStorageAndForwardsUploadProgress() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("file contents".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let seen = LockIsolated<[Int64]>([])
    let body = try HTTPBody(fileURL: url)
      .reportingProgress { bytes in seen.withValue { $0.append(bytes) } }

    // A file body must keep uploading flat from disk, so the storage kind survives wrapping and
    // the transport reports progress through `onUploadProgress` instead of iterating the chunks.
    guard case .file(let storedURL) = body.storage else {
      Issue.record("expected .file storage, got \(body.storage)")
      return
    }
    #expect(storedURL == url)
    #expect(body.length == .known(13))
    #expect(body.iterationBehavior == .multiple)

    let onUploadProgress = try #require(body.onUploadProgress)
    onUploadProgress(5)
    onUploadProgress(13)
    #expect(seen.value == [5, 13])

    // Iterating does not report again: a middleware that buffers the body must not make the
    // observer see the upload twice.
    _ = try await Data(collecting: body, upTo: 100)
    #expect(seen.value == [5, 13])
  }

  @Test
  func reportingProgressOnAStreamedBodyReportsOnlyOnPull() async throws {
    let chunks = AsyncStream<ArraySlice<UInt8>> {
      $0.yield(ArraySlice([1, 2]))
      $0.finish()
    }
    let body = HTTPBody(chunks, length: .known(2), iterationBehavior: .single)
      .reportingProgress { _ in }

    // The transport hook stays unset, so `didSendBodyData` cannot double up on the pull counter.
    #expect(body.onUploadProgress == nil)
  }
}
