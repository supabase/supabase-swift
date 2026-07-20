//
//  RetryRequestInterceptorTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 23/04/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Testing

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RetryRequestInterceptorTests {

  // MARK: - Helpers

  func makeResponse(statusCode: Int) -> Helpers.HTTPResponse {
    let urlResponse = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    return Helpers.HTTPResponse(data: Data(), response: urlResponse)
  }

  func makeInterceptor(retryLimit: Int = 2) -> RetryRequestInterceptor {
    RetryRequestInterceptor(
      retryLimit: retryLimit,
      exponentialBackoffBase: 2,
      exponentialBackoffScale: 0
    )
  }

  func makeRequest(method: HTTPTypes.HTTPRequest.Method = .get) -> Helpers.HTTPRequest {
    Helpers.HTTPRequest(url: URL(string: "https://example.com")!, method: method)
  }

  // MARK: - defaultRetryableHTTPStatusCodes

  @Test
  func defaultRetryableHTTPStatusCodesContainsStandardCodes() {
    let codes = RetryRequestInterceptor.defaultRetryableHTTPStatusCodes
    #expect(codes.contains(408))
    #expect(codes.contains(500))
    #expect(codes.contains(502))
    #expect(codes.contains(503))
    #expect(codes.contains(504))
  }

  @Test
  func defaultRetryableHTTPStatusCodesContainsCloudflareCodes() {
    let codes = RetryRequestInterceptor.defaultRetryableHTTPStatusCodes
    #expect(codes.contains(520), "520 (Cloudflare Unknown Error) should be retryable")
    #expect(codes.contains(521), "521 (Web Server Down) should be retryable")
    #expect(codes.contains(522), "522 (Connection Timed Out) should be retryable")
    #expect(codes.contains(523), "523 (Origin Is Unreachable) should be retryable")
    #expect(codes.contains(524), "524 (A Timeout Occurred) should be retryable")
    #expect(codes.contains(530), "530 (Site Frozen) should be retryable")
  }

  // MARK: - Retry behavior for Cloudflare codes

  @Test
  func retriesOnCloudflareErrorCodes() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()
    let cloudflareCodes = [520, 521, 522, 523, 524, 530]

    for code in cloudflareCodes {
      let callCount = LockIsolated(0)
      let finalResponse = try await interceptor.intercept(request) { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return self.makeResponse(statusCode: code)
        }
        return self.makeResponse(statusCode: 200)
      }
      #expect(finalResponse.statusCode == 200, "Should retry on \(code) and succeed")
      #expect(callCount.value == 2, "Should have called next twice for \(code)")
    }
  }

  @Test
  func doesNotRetryOnNonRetryableStatusCodes() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()
    let nonRetryableCodes = [400, 401, 403, 404, 422]

    for code in nonRetryableCodes {
      let callCount = LockIsolated(0)
      let response = try await interceptor.intercept(request) { _ in
        callCount.withValue { $0 += 1 }
        return self.makeResponse(statusCode: code)
      }
      #expect(response.statusCode == code)
      #expect(callCount.value == 1, "Should not retry on \(code)")
    }
  }

  @Test
  func retriesOnStandardRetryableStatusCodes() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()
    let retryableCodes = [408, 500, 502, 503, 504]

    for code in retryableCodes {
      let callCount = LockIsolated(0)
      let finalResponse = try await interceptor.intercept(request) { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return self.makeResponse(statusCode: code)
        }
        return self.makeResponse(statusCode: 200)
      }
      #expect(finalResponse.statusCode == 200, "Should retry on \(code) and succeed")
      #expect(callCount.value == 2, "Should have called next twice for \(code)")
    }
  }

  @Test
  func doesNotRetryOnNonRetryableMethod() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest(method: .post)

    let callCount = LockIsolated(0)
    let response = try await interceptor.intercept(request) { _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 500)
    }
    #expect(response.statusCode == 500)
    #expect(callCount.value == 1, "POST should not be retried")
  }

  @Test
  func respectsRetryLimit() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()

    let callCount = LockIsolated(0)
    let response = try await interceptor.intercept(request) { _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 520)
    }
    #expect(response.statusCode == 520)
    #expect(callCount.value == 2, "Should not exceed retryLimit")
  }

  // MARK: - Backoff delay

  @Test
  func awaitsFullFractionalBackoffDelay() async throws {
    let clock = RecordingClock()
    let interceptor = RetryRequestInterceptor(
      retryLimit: 2,
      exponentialBackoffBase: 2,
      exponentialBackoffScale: 0.3,
      clock: clock
    )

    let callCount = LockIsolated(0)
    let response = try await interceptor.intercept(makeRequest()) { _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: callCount.value < 2 ? 503 : 200)
    }

    #expect(response.statusCode == 200)
    #expect(callCount.value == 2)
    #expect(clock.durations.value == [.seconds(pow(2.0, 1.0) * 0.3)])
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
