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
  func multipleAuthClientInstances() throws {
    let url = URL(string: "http://localhost:54321/auth")!

    let client1Storage = InMemoryTestStorage()
    let client2Storage = InMemoryTestStorage()

    let client1 = try AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: uniqueStorageKey(),
        storage: client1Storage
      )
    )

    let client2 = try AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: uniqueStorageKey(),
        storage: client2Storage
      )
    )

    #expect(client1.clientID != client2.clientID)

    #expect(
      client1.dependencies.configuration.storage as? InMemoryTestStorage
        === client1Storage
    )
    #expect(
      client2.dependencies.configuration.storage as? InMemoryTestStorage
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
    let signingIn = try AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        storage: InMemoryTestStorage(),
        http: .init(transport: transport)
      )
    )
    let otherRequest = try AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        storage: InMemoryTestStorage()
      )
    )

    try await signingIn.signIn(email: "user@example.com", password: "secret")

    #expect(signingIn.currentSession?.accessToken == Session.valid.accessToken)
    #expect(otherRequest.currentSession == nil)
  }

  @Test
  func clientWithNoOtherOwnerDeallocates() async throws {
    let url = URL(string: "http://localhost:54321/auth")!

    weak var client: AuthClient?
    do {
      let owner = try AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          storageKey: uniqueStorageKey(),
          storage: InMemoryTestStorage()
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
  ) throws -> (subClient: T, transport: RecordingTransport) {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), body) }
    let client = try AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "http://localhost:54321/auth")!,
        storageKey: uniqueStorageKey(),
        storage: InMemoryTestStorage(),
        http: .init(transport: transport)
      )
    )
    return (subClient(client), transport)
  }

  @Test
  func oauthServerOutlivesClient() async throws {
    let (oauthServer, transport) = try releasedClientSubClient(\.oauthServer)
    try await oauthServer.client.seedSession(.valid)

    try await oauthServer.revokeGrant(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func mfaOutlivesClient() async throws {
    let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let (mfa, transport) = try releasedClientSubClient(
      \.mfa, responding: Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8))
    try await mfa.dependencies.seedSession(.valid)

    try await mfa.unenroll(factorID: factorID)

    #expect(transport.requests.count == 1)
  }

  @Test
  func deinitStopsAutoRefreshTask() async throws {
    let url = URL(string: "http://localhost:54321/auth")!

    let autoRefresh: AutoRefreshController

    do {
      let client = try AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          storageKey: uniqueStorageKey(),
          storage: InMemoryTestStorage()
        )
      )
      autoRefresh = client.dependencies.autoRefresh

      #expect(await waitUntil { await autoRefresh.isRegistered })
    }

    #expect(await waitUntil { await !autoRefresh.isRegistered })
  }
}
