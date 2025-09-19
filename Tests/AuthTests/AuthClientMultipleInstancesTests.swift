//
//  AuthClientMultipleInstancesTests.swift
//
//
//  Created by Guilherme Souza on 05/07/24.
//

import TestHelpers
import Testing

@testable import Auth

@Suite struct AuthClientMultipleInstancesTests {
  @Test("Multiple auth client instances have different IDs and isolated storage")
  func testMultipleAuthClientInstances() async {
    let url = URL(string: "http://localhost:54321/auth")!

    let client1Storage = InMemoryLocalStorage()
    let client2Storage = InMemoryLocalStorage()

    let client1 = AuthClient(
      url: url,
      configuration: AuthClient.Configuration(
        localStorage: client1Storage,
        logger: nil
      )
    )

    let client2 = AuthClient(
      url: url,
      configuration: AuthClient.Configuration(
        localStorage: client2Storage,
        logger: nil
      )
    )

    let client1ID = await client1.clientID
    let client2ID = await client2.clientID
    #expect(client1ID != client2ID)

    let client1Config = await client1.configuration
    let client2Config = await client2.configuration
    #expect(client1Config.localStorage as? InMemoryLocalStorage === client1Storage)
    #expect(client2Config.localStorage as? InMemoryLocalStorage === client2Storage)
  }
}
