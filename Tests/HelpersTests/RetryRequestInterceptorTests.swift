//
//  RetryRequestInterceptorTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 23/04/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RetryRequestInterceptorTests {

  // MARK: - Helpers

  /// Zero base delay makes the jittered wait exactly zero, so tests run instantly on any clock.
  let instant = RetryPolicy(baseDelay: .zero)

  func makeResponse(statusCode: Int, headers: HTTPFields = [:]) -> (
    HTTPTypes.HTTPResponse, HTTPBody?
  ) {
    (
      HTTPTypes.HTTPResponse(
        status: HTTPTypes.HTTPResponse.Status(code: statusCode), headerFields: headers), nil
    )
  }

  func makeInterceptor(
    _ policy: RetryPolicy? = nil, clock: any Clock<Duration> = ContinuousClock()
  ) -> RetryRequestInterceptor {
    RetryRequestInterceptor(policy: policy ?? instant, clock: clock)
  }

  func makeRequest(
    method: HTTPTypes.HTTPRequest.Method = .get, headers: HTTPFields = [:]
  ) -> HTTPTypes.HTTPRequest {
    HTTPTypes.HTTPRequest(
      method: method, url: URL(string: "https://example.com")!, headerFields: headers)
  }

  // MARK: - What is retried

  @Test
  func retriesEveryDefaultRetryableStatus() async throws {
    let interceptor = makeInterceptor()

    for code in RetryPolicy.default.retryableStatuses {
      let callCount = LockIsolated(0)
      let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        return self.makeResponse(statusCode: callCount.value < 2 ? code : 200)
      }
      #expect(head.status.code == 200, "Should retry on \(code) and succeed")
      #expect(callCount.value == 2, "Should have called next twice for \(code)")
    }
  }

  @Test
  func doesNotRetryNonRetryableStatuses() async throws {
    let interceptor = makeInterceptor()

    for code in [400, 401, 403, 404, 422] {
      let callCount = LockIsolated(0)
      let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        return self.makeResponse(statusCode: code)
      }
      #expect(head.status.code == code)
      #expect(callCount.value == 1, "Should not retry on \(code)")
    }
  }

  @Test
  func retriesTransportErrors() async throws {
    let interceptor = makeInterceptor()
    let callCount = LockIsolated(0)

    let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 { throw URLError(.networkConnectionLost) }
      return self.makeResponse(statusCode: 200)
    }
    #expect(head.status.code == 200)
    #expect(callCount.value == 2)
  }

  @Test
  func doesNotRetryErrorsThrownByUserCode() async {
    struct CustomTransportError: Error {}
    let interceptor = makeInterceptor()
    let callCount = LockIsolated(0)

    await #expect(throws: CustomTransportError.self) {
      try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        throw CustomTransportError()
      }
    }
    #expect(callCount.value == 1, "Only URLError is a transport failure worth replaying")
  }

  @Test
  func doesNotRetryNonIdempotentMethod() async throws {
    let interceptor = makeInterceptor()
    let callCount = LockIsolated(0)

    let (head, _) = try await interceptor.intercept(makeRequest(method: .post), body: nil) {
      _, _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 500)
    }
    #expect(head.status.code == 500)
    #expect(callCount.value == 1, "POST should not be retried")
  }

  @Test
  func doesNotRetryDeterministicURLErrors() async {
    let interceptor = makeInterceptor()

    for code in [URLError.Code.serverCertificateUntrusted, .badURL, .fileDoesNotExist] {
      let callCount = LockIsolated(0)
      await #expect(throws: URLError.self) {
        try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
          callCount.withValue { $0 += 1 }
          throw URLError(code)
        }
      }
      #expect(callCount.value == 1, "\(code) is not transient and should not be retried")
    }
  }

  @Test
  func respectsMaxAttempts() async throws {
    let interceptor = makeInterceptor(RetryPolicy(maxAttempts: 3, baseDelay: .zero))
    let callCount = LockIsolated(0)

    let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 503)
    }
    #expect(head.status.code == 503)
    #expect(callCount.value == 3)
  }

  @Test
  func disabledPolicyMakesOneAttempt() async throws {
    let interceptor = makeInterceptor(.disabled)
    let callCount = LockIsolated(0)

    let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 503)
    }
    #expect(head.status.code == 503)
    #expect(callCount.value == 1)
  }

  @Test
  func setsRetryCountHeaderOnRetriesOnly() async throws {
    let interceptor = makeInterceptor()
    let seen = LockIsolated<[String?]>([])

    _ = try await interceptor.intercept(makeRequest(), body: nil) { request, _ in
      seen.withValue { $0.append(request.headerFields[.xRetryCount]) }
      return self.makeResponse(statusCode: seen.value.count < 3 ? 503 : 200)
    }
    #expect(seen.value == [nil, "1", "2"])
  }

  // MARK: - Cancellation

  @Test
  func doesNotRetryCancellation() async {
    let interceptor = makeInterceptor()
    let callCount = LockIsolated(0)

    await #expect(throws: CancellationError.self) {
      try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        throw CancellationError()
      }
    }
    #expect(callCount.value == 1)
  }

  @Test
  func doesNotRetryCancelledURLError() async {
    let interceptor = makeInterceptor()
    let callCount = LockIsolated(0)

    await #expect(throws: URLError.self) {
      try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        throw URLError(.cancelled)
      }
    }
    #expect(callCount.value == 1)
  }

  @Test
  func cancelledTaskSurfacesAsCancellationErrorNotURLError() async {
    let interceptor = makeInterceptor()

    let task = Task {
      try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        // Stand in for URLSession: the exchange of a cancelled task fails with `URLError.cancelled`.
        while !Task.isCancelled { await Task.yield() }
        throw URLError(.cancelled)
      }
    }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test
  func cancellationDuringBackoffStopsRetrying() async {
    let interceptor = makeInterceptor(RetryPolicy(baseDelay: .seconds(1)), clock: CancellingClock())
    let callCount = LockIsolated(0)

    await #expect(throws: CancellationError.self) {
      try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
        callCount.withValue { $0 += 1 }
        return self.makeResponse(statusCode: 503)
      }
    }
    #expect(callCount.value == 1)
  }

  // MARK: - Bodies

  @Test
  func singleIterationBodyIsNotRetried() async throws {
    let interceptor = makeInterceptor()
    let attempts = LockIsolated(0)
    let body = HTTPBody(
      AsyncThrowingStream<ArraySlice<UInt8>, any Error> { $0.finish() },
      length: .unknown, iterationBehavior: .single)

    let (head, _) = try await interceptor.intercept(makeRequest(), body: body) { _, _ in
      attempts.withValue { $0 += 1 }
      return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil)
    }

    #expect(head.status == .serviceUnavailable)
    #expect(attempts.value == 1)
  }

  @Test
  func multipleIterationBodyIsRetried() async throws {
    let interceptor = makeInterceptor()
    let attempts = LockIsolated(0)

    let (head, _) = try await interceptor.intercept(
      makeRequest(), body: HTTPBody(Data("{}".utf8))
    ) { _, _ in
      attempts.withValue { $0 += 1 }
      return self.makeResponse(statusCode: attempts.value < 2 ? 503 : 200)
    }

    #expect(head.status.code == 200)
    #expect(attempts.value == 2)
  }

  @Test
  func discardedResponseBodyIsDrainedBeforeRetrying() async throws {
    let interceptor = makeInterceptor()
    let iterated = LockIsolated(false)
    let terminated = LockIsolated(false)
    let attempts = LockIsolated(0)

    // `makeChunks` runs only when the body is iterated, so both flags stay false unless the
    // interceptor actually drains the response it discards.
    let body = HTTPBody(storage: .stream, length: .unknown, iterationBehavior: .single) {
      iterated.setValue(true)
      return AsyncThrowingStream { continuation in
        continuation.onTermination = { _ in terminated.setValue(true) }
        // More than the drain's 1 MiB cap, so collecting throws and drops the iterator.
        for _ in 0..<3 {
          continuation.yield(ArraySlice(repeating: 0, count: 512 * 1024))
        }
        continuation.finish()
      }
    }

    let (head, _) = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      attempts.withValue { $0 += 1 }
      if attempts.value < 2 {
        return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), body)
      }
      return self.makeResponse(statusCode: 200)
    }

    #expect(head.status.code == 200)
    #expect(attempts.value == 2)
    #expect(iterated.value, "The discarded response body should be iterated")
    #expect(terminated.value, "The discarded response body's stream should terminate")
  }

  // MARK: - Delays

  @Test
  func waitsJitteredBackoffBetweenAttempts() async throws {
    let clock = RecordingClock()
    let interceptor = makeInterceptor(
      RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(60)), clock: clock)
    let callCount = LockIsolated(0)

    _ = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: callCount.value < 3 ? 503 : 200)
    }

    let durations = clock.durations.value
    #expect(durations.count == 2)
    #expect((Duration.milliseconds(500)...(.seconds(1))).contains(durations[0]))
    #expect((Duration.seconds(1)...(.seconds(2))).contains(durations[1]))
  }

  @Test
  func honoursRetryAfterHeader() async throws {
    let clock = RecordingClock()
    let interceptor = makeInterceptor(
      RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(20)), clock: clock)
    let callCount = LockIsolated(0)

    _ = try await interceptor.intercept(makeRequest(), body: nil) { _, _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return self.makeResponse(statusCode: 429, headers: [.retryAfter: "7"])
      }
      return self.makeResponse(statusCode: 200)
    }

    #expect(clock.durations.value == [.seconds(7)])
  }
}

/// A clock that records the durations it is asked to sleep for, without
/// waiting. `now` is fixed so recorded durations are exact.
struct RecordingClock: Clock {
  let anchor: ContinuousClock.Instant
  let durations: LockIsolated<[Duration]>

  init() {
    anchor = ContinuousClock().now
    durations = LockIsolated([])
  }

  var now: ContinuousClock.Instant { anchor }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
    durations.withValue { $0.append(anchor.duration(to: deadline)) }
  }
}

/// A clock whose every sleep is cancelled, standing in for a task cancelled mid-backoff.
struct CancellingClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
    throw CancellationError()
  }
}
