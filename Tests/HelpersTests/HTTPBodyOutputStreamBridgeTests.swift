//
//  HTTPBodyOutputStreamBridgeTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 15/09/26.
//

#if !canImport(FoundationNetworking)
  import ConcurrencyExtras
  import Foundation
  import Testing

  @testable import Helpers

  /// Builds bodies of `count` chunks of `size` bytes, each filled with its index, and counts how
  /// many times a consumer pulled so a test can tell whether the bridge read ahead of the reader.
  ///
  /// Goes through the package initializer with a pull-based stream on purpose: the public
  /// `HTTPBody.init(_:length:iterationBehavior:)` pumps the caller's sequence eagerly into a
  /// buffer (SDK-1833), which would hide the bridge's own pacing.
  private struct CountingChunks: Sendable {
    let count: Int
    let size: Int
    let pulls = LockIsolated(0)

    func body(length: HTTPBody.Length, iterationBehavior: HTTPBody.IterationBehavior) -> HTTPBody {
      HTTPBody(storage: .stream, length: length, iterationBehavior: iterationBehavior) {
        [pulls, count, size] in
        let index = LockIsolated(0)
        return AsyncThrowingStream {
          pulls.withValue { $0 += 1 }
          let current = index.withValue { value -> Int in
            defer { value += 1 }
            return value
          }
          return current < count ? ArraySlice(repeating: UInt8(current), count: size) : nil
        }
      }
    }

    var expectedBytes: Data {
      Data((0..<count).flatMap { Array(repeating: UInt8($0), count: size) })
    }
  }

  private func makeBoundStreams(bufferSize: Int) -> (InputStream, OutputStream) {
    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(withBufferSize: bufferSize, inputStream: &input, outputStream: &output)
    return (input!, output!)
  }

  /// Reads `input` until the writer closes its end.
  private func drain(_ input: InputStream) -> Data {
    input.open()
    defer { input.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    defer { buffer.deallocate() }
    while true {
      let read = input.read(buffer, maxLength: 64)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }

  private func poll(
    until condition: @escaping @Sendable () -> Bool, timeout: Duration = .seconds(2)
  ) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Suite
  struct HTTPBodyOutputStreamBridgeTests {
    @Test
    func writesChunksOnlyAsTheReaderDrainsThem() async throws {
      let chunks = CountingChunks(count: 8, size: 100)
      let body = chunks.body(length: .known(800), iterationBehavior: .single)
      let (input, output) = makeBoundStreams(bufferSize: 150)

      let bridge = HTTPBodyOutputStreamBridge(body: body, output: output) { error in
        Issue.record("unexpected failure: \(error)")
      }
      defer { bridge.cancel() }

      // Nobody is reading: the 150-byte buffer takes the first chunk and half of the second, so
      // the bridge holds the rest of the second and must not pull a third.
      await poll { chunks.pulls.value >= 2 }
      try await Task.sleep(for: .milliseconds(100))
      #expect(chunks.pulls.value == 2)

      let received = drain(input)
      #expect(received == chunks.expectedBytes)
      // Eight chunks plus the terminating `nil`.
      #expect(chunks.pulls.value == 9)
    }

    @Test
    func secondBridgeOverASingleBodyFails() async throws {
      let chunks = CountingChunks(count: 2, size: 10)
      let body = chunks.body(length: .unknown, iterationBehavior: .single)

      let (firstInput, firstOutput) = makeBoundStreams(bufferSize: 64)
      let first = HTTPBodyOutputStreamBridge(body: body, output: firstOutput) { error in
        Issue.record("unexpected failure: \(error)")
      }
      defer { first.cancel() }
      #expect(drain(firstInput) == chunks.expectedBytes)

      let (secondInput, secondOutput) = makeBoundStreams(bufferSize: 64)
      let failure = LockIsolated<(any Error)?>(nil)
      let second = HTTPBodyOutputStreamBridge(body: body, output: secondOutput) { error in
        failure.setValue(error)
      }
      defer { second.cancel() }

      await poll { failure.value != nil }
      #expect(failure.value is HTTPBodyAlreadyConsumedError)
      // The writer closed its end without writing anything.
      #expect(drain(secondInput).isEmpty)
    }

    @Test
    func multipleBodyReplaysOnASecondBridge() async throws {
      let chunks = CountingChunks(count: 3, size: 10)
      let body = chunks.body(length: .known(30), iterationBehavior: .multiple)

      for _ in 0..<2 {
        let (input, output) = makeBoundStreams(bufferSize: 64)
        let bridge = HTTPBodyOutputStreamBridge(body: body, output: output) { error in
          Issue.record("unexpected failure: \(error)")
        }
        defer { bridge.cancel() }
        #expect(drain(input) == chunks.expectedBytes)
      }
    }
  }
#endif
