//
//  AuthClientMultipleInstancesTests.swift
//
//
//  Created by Guilherme Souza on 05/07/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

// These tests assert on client deallocation, which only happens after the `Task { @MainActor in ...
// }` scheduled by `AuthClient.init` releases its strong reference to the client. Running them
// concurrently makes them race for the main actor, so serialize the suite.
@Suite(.serialized)
struct AuthClientMultipleInstancesTests {
  @Test
  func multipleAuthClientInstances() {
    let url = URL(string: "http://localhost:54321/auth")!

    let client1Storage = InMemoryLocalStorage()
    let client2Storage = InMemoryLocalStorage()

    let client1 = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        localStorage: client1Storage
      )
    )

    let client2 = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        localStorage: client2Storage
      )
    )

    #expect(client1.clientID != client2.clientID)

    #expect(
      client1.dependencies.configuration.localStorage as? InMemoryLocalStorage
        === client1Storage
    )
    #expect(
      client2.dependencies.configuration.localStorage as? InMemoryLocalStorage
        === client2Storage
    )
  }

  @Test
  func clientWithNoOtherOwnerDeallocates() async {
    let url = URL(string: "http://localhost:54321/auth")!

    weak var client: AuthClient?
    do {
      let owner = AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          localStorage: InMemoryLocalStorage()
        )
      )
      client = owner
      #expect(client != nil)
    }

    // `init` kicks off a `Task { @MainActor in ... }` that briefly holds a strong reference to
    // `self`, and `deinit` itself hops off to a detached task to stop auto-refresh; poll instead
    // of asserting after a single yield; the number of hops needed to actually deinit isn't fixed
    // and grows under scheduler load (e.g. on Linux CI with a small cooperative thread pool).
    for _ in 0..<100 where client != nil {
      try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
    }

    #expect(client == nil)
  }

  // MARK: - Sub-clients outlive their AuthClient (SDK-1875)

  /// Builds a client whose transport answers every request with a 200 carrying `body`, and
  /// returns only `subClient` of it, so the `AuthClient` itself is released before the caller's
  /// next line.
  private func releasedClientSubClient<T>(
    _ subClient: (AuthClient) -> T, responding body: Data = Data()
  ) -> (subClient: T, transport: RecordingTransport) {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), body) }
    let client = AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost:54321/auth")!,
        localStorage: InMemoryLocalStorage(),
        http: .init(transport: transport)
      )
    )
    return (subClient(client), transport)
  }

  @Test
  func adminOutlivesClient() async throws {
    let (admin, transport) = releasedClientSubClient(\.admin)

    try await admin.deleteUser(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func adminOAuthOutlivesClient() async throws {
    let (oauth, transport) = releasedClientSubClient(\.admin.oauth)

    try await oauth.deleteClient(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func oauthServerOutlivesClient() async throws {
    let (oauthServer, transport) = releasedClientSubClient(\.oauthServer)
    oauthServer.client.dependencies.sessionStorage.store(.valid)

    try await oauthServer.revokeGrant(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func mfaOutlivesClient() async throws {
    let factorId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let (mfa, _) = releasedClientSubClient(
      \.mfa, responding: Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8))
    mfa.client.dependencies.sessionStorage.store(.valid)

    let response = try await mfa.unenroll(params: MFAUnenrollParams(factorId: factorId))

    #expect(response.id == factorId)
  }

  @Test
  func deinitStopsAutoRefreshTask() async {
    let url = URL(string: "http://localhost:54321/auth")!

    // Held on purpose, so the auto-refresh state is still observable after the client is gone.
    let sessionManager: SessionManager

    do {
      let client = AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          localStorage: InMemoryLocalStorage()
        )
      )
      sessionManager = client.dependencies.sessionManager

      client.startAutoRefresh()

      // `startAutoRefresh()` schedules the start on a detached task, so poll instead of asserting
      // after a single yield; on a small cooperative thread pool (Linux CI) one yield is not
      // always enough for that task to have run.
      var didStart = await sessionManager.isAutoRefreshRunning()
      for _ in 0..<100 where !didStart {
        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
        didStart = await sessionManager.isAutoRefreshRunning()
      }
      #expect(didStart)
    }

    // `deinit` stops the auto-refresh loop from a detached task, so poll instead of asserting
    // right away.
    var isAutoRefreshRunning = await sessionManager.isAutoRefreshRunning()
    for _ in 0..<100 where isAutoRefreshRunning {
      try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
      isAutoRefreshRunning = await sessionManager.isAutoRefreshRunning()
    }

    #expect(isAutoRefreshRunning == false)
  }
}
