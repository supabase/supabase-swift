//
//  PresenceTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 29/10/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct PresenceTests {
  private struct User: Decodable, Equatable {
    var name: String
  }

  @Test
  func entryDecodesItsPayload() throws {
    let entry = PresenceEntry(ref: "r1", payload: ["name": "ana"])

    #expect(try entry.decode(as: User.self) == User(name: "ana"))
  }

  @Test
  func stateDecodeSkipsUndecodableEntriesAndEmptyKeys() throws {
    let state = PresenceState(entries: [
      "u1": [
        PresenceEntry(ref: "r1", payload: ["name": "ana"]),
        PresenceEntry(ref: "r2", payload: [:]),
      ],
      "u2": [PresenceEntry(ref: "r3", payload: ["age": 3])],
    ])

    let users = try state.decode(as: User.self)

    #expect(users == ["u1": [User(name: "ana")]])
  }

  @Test
  func stateDecodeThrowsOnAnUndecodableEntryWhenAsked() {
    let state = PresenceState(entries: ["u1": [PresenceEntry(ref: "r1", payload: [:])]])

    #expect(throws: DecodingError.self) {
      try state.decode(as: User.self, ignoringUndecodable: false)
    }
  }
}
