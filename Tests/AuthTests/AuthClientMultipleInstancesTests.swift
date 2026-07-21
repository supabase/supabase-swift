//
//  AuthClientMultipleInstancesTests.swift
//
//
//  Created by Guilherme Souza on 05/07/24.
//

import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
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
}
