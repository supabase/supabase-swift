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
        storageKey: uniqueStorageKey(),
        localStorage: client1Storage
      )
    )

    let client2 = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: uniqueStorageKey(),
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
  func clientsForOneProjectDoNotShareASession() async throws {
    let url = URL(string: "http://localhost:54321/auth")!
    let storageKey = uniqueStorageKey()
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(Session.valid))
    }
    let signingIn = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        localStorage: InMemoryLocalStorage(),
        http: .init(transport: transport)
      )
    )
    let otherRequest = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        localStorage: InMemoryLocalStorage()
      )
    )

    try await signingIn.signIn(email: "user@example.com", password: "secret")

    #expect(signingIn.currentSession?.accessToken == Session.valid.accessToken)
    #expect(otherRequest.currentSession == nil)
  }

  @Test
  func clientWithNoOtherOwnerDeallocates() async {
    let url = URL(string: "http://localhost:54321/auth")!

    weak var client: AuthClient?
    do {
      let owner = AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          storageKey: uniqueStorageKey(),
          localStorage: InMemoryLocalStorage()
        )
      )
      client = owner
      #expect(client != nil)
    }

    for _ in 0..<100 where client != nil {
      try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
    }

    #expect(client == nil)
  }

  private func releasedClientSubClient<T>(
    _ subClient: (AuthClient) -> T, responding body: Data = Data()
  ) -> (subClient: T, transport: RecordingTransport) {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), body) }
    let client = AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost:54321/auth")!,
        storageKey: uniqueStorageKey(),
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
    try await oauthServer.client.seedSession(.valid)

    try await oauthServer.revokeGrant(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func mfaOutlivesClient() async throws {
    let factorId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let (mfa, transport) = releasedClientSubClient(
      \.mfa, responding: Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8))
    try await mfa.dependencies.seedSession(.valid)

    try await mfa.unenroll(factorID: factorId)

    #expect(transport.requests.count == 1)
  }

  @Test
  func deinitStopsAutoRefreshTask() async {
    let url = URL(string: "http://localhost:54321/auth")!

    let autoRefresh: AutoRefreshController

    do {
      let client = AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          storageKey: uniqueStorageKey(),
          localStorage: InMemoryLocalStorage()
        )
      )
      autoRefresh = client.dependencies.autoRefresh

      #expect(await waitUntil { await autoRefresh.isRegistered })
    }

    #expect(await waitUntil { await !autoRefresh.isRegistered })
  }
}
