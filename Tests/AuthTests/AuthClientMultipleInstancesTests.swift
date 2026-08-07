//
//  AuthClientMultipleInstancesTests.swift
//
//
//  Created by Guilherme Souza on 05/07/24.
//

import ConcurrencyExtras
import Foundation
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
        localStorage: client1Storage,
        logger: nil
      )
    )

    let client2 = AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        localStorage: client2Storage,
        logger: nil
      )
    )

    #expect(client1.clientID != client2.clientID)

    #expect(
      Dependencies[client1.clientID].configuration.localStorage as? InMemoryLocalStorage
        === client1Storage
    )
    #expect(
      Dependencies[client2.clientID].configuration.localStorage as? InMemoryLocalStorage
        === client2Storage
    )
  }

  @Test
  func deinitRemovesDependenciesEntry() async {
    let url = URL(string: "http://localhost:54321/auth")!

    let clientID: AuthClientID
    do {
      let client = AuthClient(
        configuration: AuthClient.Configuration(
          url: url,
          localStorage: InMemoryLocalStorage(),
          logger: nil
        )
      )
      clientID = client.clientID
      #expect(Dependencies.instances.value[clientID] != nil)
    }

    // `init` kicks off a `Task { @MainActor in ... }` that briefly holds a
    // strong reference to `self`; let it run so `client` can actually deinit.
    await Task.megaYield()

    #expect(Dependencies.instances.value[clientID] == nil)
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
          localStorage: InMemoryLocalStorage(),
          logger: nil
        )
      )
      sessionManager = Dependencies[client.clientID].sessionManager

      await client.startAutoRefresh()
      await Task.megaYield()

      #expect(await sessionManager.isAutoRefreshRunning())
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
