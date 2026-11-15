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
  func nilDecoderReadsPostgresTimestamps() throws {
    struct Seen: Decodable, Equatable {
      var at: Date
    }
    let entry = PresenceEntry(ref: "r1", payload: ["at": "1970-01-01T00:00:00Z"])
    let state = PresenceState(entries: ["u1": [entry]])
    let expected = Seen(at: Date(timeIntervalSince1970: 0))

    #expect(try entry.decode(as: Seen.self, decoder: nil) == expected)
    #expect(try state.decode(as: Seen.self, decoder: nil) == ["u1": [expected]])
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
