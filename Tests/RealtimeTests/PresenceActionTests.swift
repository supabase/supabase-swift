//
//  PresenceActionTests.swift
//
//
//  Created by Guilherme Souza on 29/07/25.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct PresenceActionTests {

  // MARK: - PresenceV2 Tests

  @Test
  func presenceV2Initialization() {
    let ref = "test_ref_123"
    let state: JSONObject = [
      "user_id": .string("user_123"),
      "username": .string("testuser"),
      "status": .string("online"),
    ]

    let presence = PresenceV2(ref: ref, state: state)

    #expect(presence.ref == ref)
    #expect(presence.state["user_id"]?.stringValue == "user_123")
    #expect(presence.state["username"]?.stringValue == "testuser")
    #expect(presence.state["status"]?.stringValue == "online")
  }

  @Test
  func presenceV2Hashable() {
    let state: JSONObject = ["key": .string("value")]
    let presence1 = PresenceV2(ref: "ref1", state: state)
    let presence2 = PresenceV2(ref: "ref1", state: state)
    let presence3 = PresenceV2(ref: "ref2", state: state)

    #expect(presence1 == presence2)
    #expect(presence1 != presence3)

    let set = Set([presence1, presence2, presence3])
    #expect(set.count == 2)  // presence1 and presence2 are equal
  }

  // MARK: - PresenceV2 Codable Tests

  @Test
  func presenceV2DecodingValidData() throws {
    let jsonData = """
      {
        "metas": [
          {
            "phx_ref": "presence_ref_123",
            "user_id": "user_456",
            "username": "johndoe",
            "status": "active",
            "extra_field": "extra_value"
          }
        ]
      }
      """.data(using: .utf8)!

    let presence = try JSONDecoder().decode(PresenceV2.self, from: jsonData)

    #expect(presence.ref == "presence_ref_123")
    #expect(presence.state["user_id"]?.stringValue == "user_456")
    #expect(presence.state["username"]?.stringValue == "johndoe")
    #expect(presence.state["status"]?.stringValue == "active")
    #expect(presence.state["extra_field"]?.stringValue == "extra_value")

    // Ensure phx_ref is not in the state
    #expect(presence.state["phx_ref"] == nil)
  }

  @Test
  func presenceV2DecodingWithMultipleMetas() throws {
    // Should use the first meta object
    let jsonData = """
      {
        "metas": [
          {
            "phx_ref": "first_ref",
            "user_id": "first_user"
          },
          {
            "phx_ref": "second_ref",
            "user_id": "second_user"
          }
        ]
      }
      """.data(using: .utf8)!

    let presence = try JSONDecoder().decode(PresenceV2.self, from: jsonData)

    #expect(presence.ref == "first_ref")
    #expect(presence.state["user_id"]?.stringValue == "first_user")
  }

  @Test
  func presenceV2DecodingMissingMetas() {
    let jsonData = """
      {
        "other_field": "value"
      }
      """.data(using: .utf8)!

    #expect {
      try JSONDecoder().decode(PresenceV2.self, from: jsonData)
    } throws: { error in
      guard let decodingError = error as? DecodingError,
        case .typeMismatch(let type, let context) = decodingError
      else {
        return false
      }
      return type == JSONObject.self
        && context.debugDescription == "A presence should at least have a phx_ref."
    }
  }

  @Test
  func presenceV2DecodingEmptyMetas() {
    let jsonData = """
      {
        "metas": []
      }
      """.data(using: .utf8)!

    #expect {
      try JSONDecoder().decode(PresenceV2.self, from: jsonData)
    } throws: { error in
      guard let decodingError = error as? DecodingError,
        case .typeMismatch(let type, let context) = decodingError
      else {
        return false
      }
      return type == JSONObject.self
        && context.debugDescription == "A presence should at least have a phx_ref."
    }
  }

  @Test
  func presenceV2DecodingMissingPhxRef() {
    let jsonData = """
      {
        "metas": [
          {
            "user_id": "user_123",
            "username": "testuser"
          }
        ]
      }
      """.data(using: .utf8)!

    #expect {
      try JSONDecoder().decode(PresenceV2.self, from: jsonData)
    } throws: { error in
      guard let decodingError = error as? DecodingError,
        case .typeMismatch(let type, let context) = decodingError
      else {
        return false
      }
      return type == String.self
        && context.debugDescription == "A presence should at least have a phx_ref."
    }
  }

  @Test
  func presenceV2DecodingNonStringPhxRef() {
    let jsonData = """
      {
        "metas": [
          {
            "phx_ref": 123,
            "user_id": "user_123"
          }
        ]
      }
      """.data(using: .utf8)!

    #expect {
      try JSONDecoder().decode(PresenceV2.self, from: jsonData)
    } throws: { error in
      guard let decodingError = error as? DecodingError,
        case .typeMismatch(let type, let context) = decodingError
      else {
        return false
      }
      return type == String.self
        && context.debugDescription == "A presence should at least have a phx_ref."
    }
  }

  @Test
  func presenceV2Encoding() throws {
    let state: JSONObject = [
      "user_id": .string("user_789"),
      "status": .string("online"),
      "count": .integer(42),
    ]
    let presence = PresenceV2(ref: "test_ref", state: state)

    let encodedData = try JSONEncoder().encode(presence)
    let decodedDict = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]

    #expect(decodedDict != nil)
    #expect(decodedDict?["phx_ref"] as? String == "test_ref")

    let stateDict = decodedDict?["state"] as? [String: Any]
    #expect(stateDict != nil)
    #expect(stateDict?["user_id"] as? String == "user_789")
    #expect(stateDict?["status"] as? String == "online")
    #expect(stateDict?["count"] as? Int == 42)
  }

  // MARK: - PresenceV2 decodeState Tests

  struct TestUser: Codable, Equatable {
    let id: String
    let name: String
    let age: Int
  }

  @Test
  func decodeStateSuccess() throws {
    let state: JSONObject = [
      "id": .string("user_123"),
      "name": .string("John Doe"),
      "age": .integer(30),
    ]
    let presence = PresenceV2(ref: "ref", state: state)

    let user = try presence.decodeState(as: TestUser.self)

    #expect(user.id == "user_123")
    #expect(user.name == "John Doe")
    #expect(user.age == 30)
  }

  @Test
  func decodeStateWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let state: JSONObject = [
      "user_id": .string("user_456"),
      "user_name": .string("Jane Doe"),
      "user_age": .integer(25),
    ]
    let presence = PresenceV2(ref: "ref", state: state)

    struct SnakeCaseUser: Codable, Equatable {
      let userId: String
      let userName: String
      let userAge: Int
    }

    let user = try presence.decodeState(as: SnakeCaseUser.self, decoder: customDecoder)

    #expect(user.userId == "user_456")
    #expect(user.userName == "Jane Doe")
    #expect(user.userAge == 25)
  }

  @Test
  func decodeStateFailure() {
    let state: JSONObject = [
      "id": .string("user_123"),
      "name": .string("John Doe"),
      // Missing required age field
    ]
    let presence = PresenceV2(ref: "ref", state: state)

    #expect(throws: (any Error).self) {
      try presence.decodeState(as: TestUser.self)
    }
  }

  // MARK: - PresenceAction Protocol Extension Tests

  struct MockPresenceAction: PresenceAction {
    let joins: [String: PresenceV2]
    let leaves: [String: PresenceV2]
    let rawMessage: RealtimeMessageV2
  }

  @Test
  func decodeJoinsWithIgnoreOtherTypes() throws {
    let validState1: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25),
    ]
    let validState2: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      "age": .integer(30),
    ]
    let invalidState: JSONObject = [
      "id": .string("user_3"),
      "name": .string("Charlie"),
      // Missing age field
    ]

    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState1),
      "key2": PresenceV2(ref: "ref2", state: validState2),
      "key3": PresenceV2(ref: "ref3", state: invalidState),
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)

    // With ignoreOtherTypes = true (default), should return only valid users
    let users = try action.decodeJoins(as: TestUser.self)
    #expect(users.count == 2)
    #expect(users.contains(TestUser(id: "user_1", name: "Alice", age: 25)))
    #expect(users.contains(TestUser(id: "user_2", name: "Bob", age: 30)))
  }

  @Test
  func decodeJoinsWithoutIgnoreOtherTypes() {
    let validState: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25),
    ]
    let invalidState: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      // Missing age field
    ]

    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState),
      "key2": PresenceV2(ref: "ref2", state: invalidState),
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)

    // With ignoreOtherTypes = false, should throw on invalid data
    #expect(throws: (any Error).self) {
      try action.decodeJoins(as: TestUser.self, ignoreOtherTypes: false)
    }
  }

  @Test
  func decodeLeavesWithIgnoreOtherTypes() throws {
    let validState1: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25),
    ]
    let validState2: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      "age": .integer(30),
    ]
    let invalidState: JSONObject = [
      "id": .string("user_3"),
      "name": .string("Charlie"),
      // Missing age field
    ]

    let leaves: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState1),
      "key2": PresenceV2(ref: "ref2", state: validState2),
      "key3": PresenceV2(ref: "ref3", state: invalidState),
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: [:], leaves: leaves, rawMessage: rawMessage)

    // With ignoreOtherTypes = true (default), should return only valid users
    let users = try action.decodeLeaves(as: TestUser.self)
    #expect(users.count == 2)
    #expect(users.contains(TestUser(id: "user_1", name: "Alice", age: 25)))
    #expect(users.contains(TestUser(id: "user_2", name: "Bob", age: 30)))
  }

  @Test
  func decodeLeavesWithoutIgnoreOtherTypes() {
    let validState: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25),
    ]
    let invalidState: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      // Missing age field
    ]

    let leaves: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState),
      "key2": PresenceV2(ref: "ref2", state: invalidState),
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: [:], leaves: leaves, rawMessage: rawMessage)

    // With ignoreOtherTypes = false, should throw on invalid data
    #expect(throws: (any Error).self) {
      try action.decodeLeaves(as: TestUser.self, ignoreOtherTypes: false)
    }
  }

  @Test
  func decodeJoinsWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase

    let state: JSONObject = [
      "user_id": .string("user_123"),
      "user_name": .string("Test User"),
      "user_age": .integer(28),
    ]

    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: state)
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)

    struct SnakeCaseUser: Codable, Equatable {
      let userId: String
      let userName: String
      let userAge: Int
    }

    let users = try action.decodeJoins(as: SnakeCaseUser.self, decoder: customDecoder)
    #expect(users.count == 1)
    #expect(users.first?.userId == "user_123")
    #expect(users.first?.userName == "Test User")
    #expect(users.first?.userAge == 28)
  }

  @Test
  func decodeEmptyJoinsAndLeaves() throws {
    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: [:], leaves: [:], rawMessage: rawMessage)

    let joinUsers = try action.decodeJoins(as: TestUser.self)
    let leaveUsers = try action.decodeLeaves(as: TestUser.self)

    #expect(joinUsers.count == 0)
    #expect(leaveUsers.count == 0)
  }

  // MARK: - PresenceActionImpl Tests

  @Test
  func presenceActionImplInitialization() {
    let joins: [String: PresenceV2] = [
      "user1": PresenceV2(ref: "ref1", state: ["name": .string("User 1")])
    ]
    let leaves: [String: PresenceV2] = [
      "user2": PresenceV2(ref: "ref2", state: ["name": .string("User 2")])
    ]
    let rawMessage = RealtimeMessageV2(
      joinRef: "join_ref", ref: "ref", topic: "topic", event: "event",
      payload: ["key": .string("value")]
    )

    let impl = PresenceActionImpl(joins: joins, leaves: leaves, rawMessage: rawMessage)

    #expect(impl.joins.count == 1)
    #expect(impl.leaves.count == 1)
    #expect(impl.joins["user1"]?.ref == "ref1")
    #expect(impl.leaves["user2"]?.ref == "ref2")
    #expect(impl.rawMessage.topic == "topic")
    #expect(impl.rawMessage.event == "event")
  }

  @Test
  func presenceActionImplConformsToProtocol() {
    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let impl = PresenceActionImpl(joins: [:], leaves: [:], rawMessage: rawMessage)

    // Test that it can be used as PresenceAction
    let presenceAction: any PresenceAction = impl
    #expect(presenceAction.joins.count == 0)
    #expect(presenceAction.leaves.count == 0)
    #expect(presenceAction.rawMessage.topic == "test")
  }

  // MARK: - Edge Cases and Complex Scenarios

  @Test
  func presenceV2WithComplexNestedState() throws {
    let complexState: JSONObject = [
      "user": .object([
        "id": .string("123"),
        "profile": .object([
          "name": .string("John"),
          "preferences": .object([
            "theme": .string("dark"),
            "notifications": .bool(true),
          ]),
        ]),
        "tags": .array([.string("admin"), .string("developer")]),
      ]),
      "metadata": .object([
        "last_seen": .string("2024-01-01T00:00:00Z"),
        "connection_count": .integer(3),
      ]),
    ]

    let presence = PresenceV2(ref: "complex_ref", state: complexState)

    #expect(presence.ref == "complex_ref")
    #expect(presence.state["user"]?.objectValue?["id"]?.stringValue == "123")
    #expect(
      presence.state["user"]?.objectValue?["profile"]?.objectValue?["name"]?.stringValue
        == "John"
    )
    #expect(
      presence.state["user"]?.objectValue?["profile"]?.objectValue?["preferences"]?.objectValue?[
        "theme"]?.stringValue
        == "dark"
    )
    #expect(presence.state["user"]?.objectValue?["tags"]?.arrayValue?.count == 2)
    #expect(presence.state["metadata"]?.objectValue?["connection_count"]?.intValue == 3)
  }

  @Test
  func presenceV2RoundTripCoding() throws {
    let originalState: JSONObject = [
      "user_id": .string("user_789"),
      "status": .string("online"),
      "score": .double(98.5),
      "active": .bool(true),
      "tags": .array([.string("tag1"), .string("tag2")]),
      "metadata": .object(["key": .string("value")]),
    ]
    let originalPresence = PresenceV2(ref: "original_ref", state: originalState)

    // Test that encoding works (we don't need the actual data for this test)
    _ = try JSONEncoder().encode(originalPresence)

    // Create the expected server format manually by adding the state to metas with phx_ref
    let stateWithRef = originalState.merging(["phx_ref": .string(originalPresence.ref)]) { _, new in
      new
    }
    let serverFormat: [String: Any] = [
      "metas": [
        stateWithRef.mapValues(\.value)
      ]
    ]

    let serverData = try JSONSerialization.data(withJSONObject: serverFormat)
    let decodedPresence = try JSONDecoder().decode(PresenceV2.self, from: serverData)

    #expect(decodedPresence.ref == originalPresence.ref)
    #expect(decodedPresence.state["user_id"]?.stringValue == "user_789")
    #expect(decodedPresence.state["status"]?.stringValue == "online")
    #expect(decodedPresence.state["score"]?.doubleValue == 98.5)
    #expect(decodedPresence.state["active"]?.boolValue == true)
    #expect(decodedPresence.state["tags"]?.arrayValue?.count == 2)
    #expect(decodedPresence.state["metadata"]?.objectValue != nil)
  }

  @Test
  func presenceActionWithMixedValidAndInvalidData() throws {
    struct PartialUser: Codable {
      let id: String
      let name: String?
    }

    let validState: JSONObject = [
      "id": .string("valid_user"),
      "name": .string("Valid User"),
    ]
    let partialState: JSONObject = [
      "id": .string("partial_user")
      // name is optional, so this should still decode
    ]
    let invalidState: JSONObject = [
      "name": .string("No ID User")
      // missing required id field
    ]

    let joins: [String: PresenceV2] = [
      "valid": PresenceV2(ref: "ref1", state: validState),
      "partial": PresenceV2(ref: "ref2", state: partialState),
      "invalid": PresenceV2(ref: "ref3", state: invalidState),
    ]

    let rawMessage = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )

    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)

    // With ignoreOtherTypes = true, should get valid and partial users
    let users = try action.decodeJoins(as: PartialUser.self, ignoreOtherTypes: true)
    #expect(users.count == 2)

    let userIds = users.map(\.id).sorted()
    #expect(userIds == ["partial_user", "valid_user"])
  }
}
