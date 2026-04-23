//
//  RetryRequestInterceptorTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 23/04/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import XCTest

@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class RetryRequestInterceptorTests: XCTestCase {

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

  func testDefaultRetryableHTTPStatusCodesContainsStandardCodes() {
    let codes = RetryRequestInterceptor.defaultRetryableHTTPStatusCodes
    XCTAssertTrue(codes.contains(408))
    XCTAssertTrue(codes.contains(500))
    XCTAssertTrue(codes.contains(502))
    XCTAssertTrue(codes.contains(503))
    XCTAssertTrue(codes.contains(504))
  }

  func testDefaultRetryableHTTPStatusCodesContainsCloudfareCodes() {
    let codes = RetryRequestInterceptor.defaultRetryableHTTPStatusCodes
    XCTAssertTrue(codes.contains(520), "520 (Cloudflare Unknown Error) should be retryable")
    XCTAssertTrue(codes.contains(521), "521 (Web Server Down) should be retryable")
    XCTAssertTrue(codes.contains(522), "522 (Connection Timed Out) should be retryable")
    XCTAssertTrue(codes.contains(523), "523 (Origin Is Unreachable) should be retryable")
    XCTAssertTrue(codes.contains(524), "524 (A Timeout Occurred) should be retryable")
    XCTAssertTrue(codes.contains(530), "530 (Site Frozen) should be retryable")
  }

  // MARK: - Retry behavior for Cloudflare codes

  func testRetriesOnCloudflareErrorCodes() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()
    let cloudfareCodes = [520, 521, 522, 523, 524, 530]

    for code in cloudfareCodes {
      let callCount = LockIsolated(0)
      let finalResponse = try await interceptor.intercept(request) { _ in
        callCount.withValue { $0 += 1 }
        if callCount.value < 2 {
          return self.makeResponse(statusCode: code)
        }
        return self.makeResponse(statusCode: 200)
      }
      XCTAssertEqual(finalResponse.statusCode, 200, "Should retry on \(code) and succeed")
      XCTAssertEqual(callCount.value, 2, "Should have called next twice for \(code)")
    }
  }

  func testDoesNotRetryOnNonRetryableStatusCodes() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()
    let nonRetryableCodes = [400, 401, 403, 404, 422]

    for code in nonRetryableCodes {
      let callCount = LockIsolated(0)
      let response = try await interceptor.intercept(request) { _ in
        callCount.withValue { $0 += 1 }
        return self.makeResponse(statusCode: code)
      }
      XCTAssertEqual(response.statusCode, code)
      XCTAssertEqual(callCount.value, 1, "Should not retry on \(code)")
    }
  }

  func testRetriesOnStandardRetryableStatusCodes() async throws {
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
      XCTAssertEqual(finalResponse.statusCode, 200, "Should retry on \(code) and succeed")
      XCTAssertEqual(callCount.value, 2, "Should have called next twice for \(code)")
    }
  }

  func testDoesNotRetryOnNonRetryableMethod() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest(method: .post)

    let callCount = LockIsolated(0)
    let response = try await interceptor.intercept(request) { _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 500)
    }
    XCTAssertEqual(response.statusCode, 500)
    XCTAssertEqual(callCount.value, 1, "POST should not be retried")
  }

  func testRespectsRetryLimit() async throws {
    let interceptor = makeInterceptor(retryLimit: 2)
    let request = makeRequest()

    let callCount = LockIsolated(0)
    let response = try await interceptor.intercept(request) { _ in
      callCount.withValue { $0 += 1 }
      return self.makeResponse(statusCode: 520)
    }
    XCTAssertEqual(response.statusCode, 520)
    XCTAssertEqual(callCount.value, 2, "Should not exceed retryLimit")
  }
}
