//
//  APIClientTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 15/09/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Auth

@Suite
struct APIClientTests {
  @Test
  func rateLimitedRequestIsNotRetried() async throws {
    // GoTrue's limiters count every attempt and their windows are minutes long, so replaying a
    // 429 within seconds only burns quota.
    let attempts = LockIsolated(0)
    let http = HTTPClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost/auth/v1")!,
        storageKey: uniqueStorageKey(),
        localStorage: InMemoryLocalStorage(),
        http: .init(
          transport: ClosureTransport { _, _ in
            attempts.withValue { $0 += 1 }
            return (HTTPTypes.HTTPResponse(status: .tooManyRequests), nil)
          })
      ))

    let (response, _) = try await http.send(
      HTTPTypes.HTTPRequest(method: .post, url: URL(string: "http://localhost/auth/v1/otp")!))

    #expect(response.status == .tooManyRequests)
    #expect(attempts.value == 1)
  }

  @Test
  func tokenRequestIsNotReplayedAfterATimeout() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient { _ in
      attempts.withValue { $0 += 1 }
      throw URLError(.timedOut)
    }

    await #expect(throws: AuthError.self) {
      try await client.execute(authAPI.refreshSession(refreshToken: "refresh-token"))
    }
    #expect(attempts.value == 1)
  }

  @Test
  func otpRequestIsNotReplayed() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient { _ in
      attempts.withValue { $0 += 1 }
      throw URLError(.timedOut)
    }

    await #expect(throws: AuthError.self) {
      try await client.execute(
        authAPI.signInWithOTP(
          email: "a@b.c", redirectTo: nil, shouldCreateUser: true, data: nil, captchaToken: nil,
          pkce: nil))
    }
    #expect(attempts.value == 1)
  }

  @Test
  func tokenRequestIsNotReplayedAfterAServerError() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient { _ in
      attempts.withValue { $0 += 1 }
      return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), Data())
    }

    await #expect(throws: AuthError.self) {
      try await client.execute(authAPI.refreshSession(refreshToken: "refresh-token"))
    }
    #expect(attempts.value == 1)
  }

  @Test
  func tokenRequestIsRetriedAfterAConnectionFailure() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient { _ in
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      if attempt == 1 { throw URLError(.cannotConnectToHost) }
      return (HTTPTypes.HTTPResponse(status: .ok), MockData.session)
    }

    let session = try await client.execute(authAPI.refreshSession(refreshToken: "refresh-token"))

    #expect(session.refreshToken == "GGduTeu95GraIXQ56jppkw")
    #expect(attempts.value == 2)
  }

  @Test
  func getRequestIsStillRetriedAfterATimeout() async throws {
    let attempts = LockIsolated(0)
    let client = makeClient { _ in
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      if attempt == 1 { throw URLError(.timedOut) }
      return (HTTPTypes.HTTPResponse(status: .ok), MockData.user)
    }

    _ = try await client.execute(authAPI.user(accessToken: "access-token"))

    #expect(attempts.value == 2)
  }

  @Test
  func onlyGetRequestsRetryBeyondConnectionFailures() throws {
    #expect(try authAPI.refreshSession(refreshToken: "r").retriesOnlyConnectionFailures)
    #expect(authAPI.signOut(accessToken: "a", scope: .global).retriesOnlyConnectionFailures)
    #expect(!authAPI.user(accessToken: "a").retriesOnlyConnectionFailures)
  }

  private let authAPI = AuthAPI(
    url: URL(string: "http://localhost/auth/v1")!,
    headers: [:],
    defaultRedirectURL: nil,
    encoder: AuthClient.Configuration.jsonEncoder,
    decoder: AuthClient.Configuration.jsonDecoder
  )

  private func makeClient(
    _ respond: @escaping @Sendable (HTTPTypes.HTTPRequest) throws -> (HTTPTypes.HTTPResponse, Data)
  ) -> APIClient {
    APIClient(
      http: HTTPClient(
        configuration: AuthClient.Configuration(
          url: URL(string: "http://localhost/auth/v1")!,
          storageKey: uniqueStorageKey(),
          localStorage: InMemoryLocalStorage(),
          http: .init(
            transport: ClosureTransport { request, _ in
              let (response, data) = try respond(request)
              return (response, HTTPBody(data))
            }),
          clock: ImmediateClock()
        )))
  }
}
