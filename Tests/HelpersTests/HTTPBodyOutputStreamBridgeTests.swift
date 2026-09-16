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
  /// Goes through the package initializer so the pull counter sits right at the source, with no
  /// wrapping sequence between it and the bridge.
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

  /// Reads `input` until the writer closes its end, on a global queue. A bound pair's blocking
  /// read spins the calling thread's run loop while it waits, so it must never run on the test's
  /// own thread: in a full parallel run Swift Testing can place the test on the main thread, and
  /// parking the main run loop there deadlocks everything else that needs it.
  private func drain(_ input: InputStream) async -> Data {
    let input = UncheckedSendable(input)
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        let stream = input.value
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        defer { buffer.deallocate() }
        while true {
          let read = stream.read(buffer, maxLength: 64)
          guard read > 0 else { break }
          data.append(buffer, count: read)
        }
        continuation.resume(returning: data)
      }
    }
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

      let received = await drain(input)
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
      #expect(await drain(firstInput) == chunks.expectedBytes)

      let (secondInput, secondOutput) = makeBoundStreams(bufferSize: 64)
      let failure = LockIsolated<(any Error)?>(nil)
      let second = HTTPBodyOutputStreamBridge(body: body, output: secondOutput) { error in
        failure.setValue(error)
      }
      defer { second.cancel() }

      await poll { failure.value != nil }
      #expect(failure.value is HTTPBodyAlreadyConsumedError)
      // The writer closed its end without writing anything.
      #expect(await drain(secondInput).isEmpty)
    }

    @Test
    func bodyShorterThanDeclaredLengthFails() async throws {
      let chunks = CountingChunks(count: 2, size: 10)
      let body = chunks.body(length: .known(30), iterationBehavior: .single)
      let (input, output) = makeBoundStreams(bufferSize: 64)
      let failure = LockIsolated<(any Error)?>(nil)
      let bridge = HTTPBodyOutputStreamBridge(body: body, output: output) { failure.setValue($0) }
      defer { bridge.cancel() }

      // Content-Length promised 30 bytes; the stream closes after 20 so the request fails instead
      // of hanging until URLSession's timeout.
      #expect(await drain(input) == chunks.expectedBytes)
      await poll { failure.value != nil }
      let error = try #require(failure.value as? HTTPBodyLengthMismatchError)
      #expect(error.declared == 30)
      #expect(error.actual == 20)
    }

    @Test
    func bodyLongerThanDeclaredLengthFails() async throws {
      let chunks = CountingChunks(count: 3, size: 10)
      let body = chunks.body(length: .known(20), iterationBehavior: .single)
      let (input, output) = makeBoundStreams(bufferSize: 64)
      let failure = LockIsolated<(any Error)?>(nil)
      let bridge = HTTPBodyOutputStreamBridge(body: body, output: output) { failure.setValue($0) }
      defer { bridge.cancel() }

      // The third chunk would overrun Content-Length; it is never written.
      #expect(await drain(input) == chunks.expectedBytes.prefix(20))
      await poll { failure.value != nil }
      let error = try #require(failure.value as? HTTPBodyLengthMismatchError)
      #expect(error.declared == 20)
      #expect(error.actual == 30)
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
        #expect(await drain(input) == chunks.expectedBytes)
      }
    }
  }
#endif
