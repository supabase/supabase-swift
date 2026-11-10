//
//  AccessTokenMiddlewareTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import Helpers

@Suite
struct AccessTokenMiddlewareTests {
  struct TokenError: Error {}

  let request = HTTPTypes.HTTPRequest(method: .get, scheme: "https", authority: "a.b", path: "/")

  func send(
    _ request: HTTPTypes.HTTPRequest,
    token: @escaping @Sendable () async throws -> String?
  ) async throws -> String? {
    try await AccessTokenMiddleware(getAccessToken: token)
      .intercept(request, body: nil) { request, _ in
        (HTTPTypes.HTTPResponse(status: .ok, headerFields: request.headerFields), nil)
      }
      .0.headerFields[.authorization]
  }

  @Test
  func setsTheBearerWhenTheRequestCarriesNoAuthorization() async throws {
    #expect(try await send(request) { "token" } == "Bearer token")
  }

  @Test
  func leavesAnExistingAuthorizationAlone() async throws {
    var request = request
    request.headerFields[.authorization] = "Bearer per-call"
    #expect(try await send(request) { "token" } == "Bearer per-call")
  }

  @Test
  func sendsNoAuthorizationForANilToken() async throws {
    #expect(try await send(request) { nil } == nil)
  }

  @Test
  func wrapsTheProviderErrorSoTheModuleCanMapIt() async {
    let failure = await #expect(throws: AccessTokenFailure.self) {
      try await send(request) { throw TokenError() }
    }
    #expect(failure?.underlyingError is TokenError)
  }

  @Test
  func failureDescribesItselfWithTheProviderError() {
    struct DescribedError: LocalizedError, CustomStringConvertible {
      var description: String { "described" }
      var errorDescription: String? { "localized" }
    }
    let failure = AccessTokenFailure(underlyingError: DescribedError())

    #expect(failure.description == "described")
    #expect(failure.localizedDescription == "localized")
  }

  @Test
  func passesCancellationThroughUnwrapped() async {
    await #expect(throws: CancellationError.self) {
      try await send(request) { throw CancellationError() }
    }
  }

  @Test
  func mapsTheURLErrorOfACancelledTaskToCancellationError() async {
    await #expect(throws: CancellationError.self) {
      try await send(request) {
        withUnsafeCurrentTask { $0?.cancel() }
        throw URLError(.cancelled)
      }
    }
  }

  @Test
  func wrapsACancelledURLErrorWithoutTaskCancellation() async {
    let failure = await #expect(throws: AccessTokenFailure.self) {
      try await send(request) { throw URLError(.cancelled) }
    }
    #expect((failure?.underlyingError as? URLError)?.code == .cancelled)
  }

  @Test
  func doesNotCallTheProviderWhenTheRequestCarriesAuthorization() async throws {
    var request = request
    request.headerFields[.authorization] = "Bearer static"
    #expect(try await send(request) { throw TokenError() } == "Bearer static")
  }
}
