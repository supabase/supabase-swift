//
//  PresenceDecodeTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers
import Testing

@testable import RealtimeV3

// MARK: - Test Helpers

private struct UserPresence: Codable, Sendable, Equatable {
  let userId: String
  let status: String
}

// MARK: - PresenceDecodeTests

@Suite struct PresenceDecodeTests {

  // MARK: - decodePresenceState

  /// Verifies that a `presence_state` payload is decoded into `[PresenceKey: [T]]`.
  @Test func decodesPresenceState() throws {
    // Build a JSONValue representing:
    // { "u1": {"metas":[{"phx_ref":"r1","userId":"u1","status":"active"}]},
    //   "u2": {"metas":[{"phx_ref":"r2","userId":"u2","status":"idle"}]} }
    let json: JSONValue = .object([
      "u1": .object([
        "metas": .array([
          .object([
            "phx_ref": .string("r1"),
            "userId": .string("u1"),
            "status": .string("active"),
          ])
        ])
      ]),
      "u2": .object([
        "metas": .array([
          .object([
            "phx_ref": .string("r2"),
            "userId": .string("u2"),
            "status": .string("idle"),
          ])
        ])
      ]),
    ])

    let active = try decodePresenceState(json, as: UserPresence.self)

    #expect(active["u1"] == [UserPresence(userId: "u1", status: "active")])
    #expect(active["u2"] == [UserPresence(userId: "u2", status: "idle")])
  }

  /// Verifies that an empty `presence_state` payload `{}` decodes to `[:]`.
  @Test func decodesEmptyPresenceState() throws {
    let json: JSONValue = .object([:])
    let active = try decodePresenceState(json, as: UserPresence.self)
    #expect(active.isEmpty)
  }

  // MARK: - decodePresenceDiff

  /// Verifies that a `presence_diff` payload is decoded into `PresenceDiff<T>`.
  @Test func decodesPresenceDiff() throws {
    // Build a JSONValue representing:
    // { "joins": {"u3":{"metas":[{"phx_ref":"r3","userId":"u3","status":"active"}]}},
    //   "leaves": {"u1":{"metas":[{"phx_ref":"r1","userId":"u1","status":"active"}]}} }
    let json: JSONValue = .object([
      "joins": .object([
        "u3": .object([
          "metas": .array([
            .object([
              "phx_ref": .string("r3"),
              "userId": .string("u3"),
              "status": .string("active"),
            ])
          ])
        ])
      ]),
      "leaves": .object([
        "u1": .object([
          "metas": .array([
            .object([
              "phx_ref": .string("r1"),
              "userId": .string("u1"),
              "status": .string("active"),
            ])
          ])
        ])
      ]),
    ])

    let diff = try decodePresenceDiff(json, as: UserPresence.self)

    // Check joined contains ("u3", UserPresence(userId: "u3", status: "active"))
    let joinedKeys = diff.joined.map { $0.0 }
    let joinedValues = diff.joined.map { $0.1 }
    #expect(joinedKeys.contains("u3"))
    let u3Index = joinedKeys.firstIndex(of: "u3")!
    #expect(joinedValues[u3Index] == UserPresence(userId: "u3", status: "active"))

    // Check left contains ("u1", UserPresence(userId: "u1", status: "active"))
    let leftKeys = diff.left.map { $0.0 }
    let leftValues = diff.left.map { $0.1 }
    #expect(leftKeys.contains("u1"))
    let u1Index = leftKeys.firstIndex(of: "u1")!
    #expect(leftValues[u1Index] == UserPresence(userId: "u1", status: "active"))
  }
}
