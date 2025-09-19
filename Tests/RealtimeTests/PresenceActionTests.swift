//
//  PresenceActionTests.swift
//
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class PresenceActionTests: XCTestCase {
  
  // MARK: - PresenceV2 Tests
  
  func testPresenceV2Initialization() {
    let ref = "test_ref_123"
    let state: JSONObject = [
      "user_id": .string("user_123"),
      "username": .string("testuser"),
      "status": .string("online")
    ]
    
    let presence = PresenceV2(ref: ref, state: state)
    
    XCTAssertEqual(presence.ref, ref)
    XCTAssertEqual(presence.state["user_id"]?.stringValue, "user_123")
    XCTAssertEqual(presence.state["username"]?.stringValue, "testuser")
    XCTAssertEqual(presence.state["status"]?.stringValue, "online")
  }
  
  func testPresenceV2Hashable() {
    let state: JSONObject = ["key": .string("value")]
    let presence1 = PresenceV2(ref: "ref1", state: state)
    let presence2 = PresenceV2(ref: "ref1", state: state)
    let presence3 = PresenceV2(ref: "ref2", state: state)
    
    XCTAssertEqual(presence1, presence2)
    XCTAssertNotEqual(presence1, presence3)
    
    let set = Set([presence1, presence2, presence3])
    XCTAssertEqual(set.count, 2) // presence1 and presence2 are equal
  }
  
  // MARK: - PresenceV2 Codable Tests
  
  func testPresenceV2DecodingValidData() throws {
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
    
    XCTAssertEqual(presence.ref, "presence_ref_123")
    XCTAssertEqual(presence.state["user_id"]?.stringValue, "user_456")
    XCTAssertEqual(presence.state["username"]?.stringValue, "johndoe")
    XCTAssertEqual(presence.state["status"]?.stringValue, "active")
    XCTAssertEqual(presence.state["extra_field"]?.stringValue, "extra_value")
    
    // Ensure phx_ref is not in the state
    XCTAssertNil(presence.state["phx_ref"])
  }
  
  func testPresenceV2DecodingWithMultipleMetas() throws {
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
    
    XCTAssertEqual(presence.ref, "first_ref")
    XCTAssertEqual(presence.state["user_id"]?.stringValue, "first_user")
  }
  
  func testPresenceV2DecodingMissingMetas() {
    let jsonData = """
    {
      "other_field": "value"
    }
    """.data(using: .utf8)!
    
    XCTAssertThrowsError(try JSONDecoder().decode(PresenceV2.self, from: jsonData)) { error in
      guard let decodingError = error as? DecodingError,
            case .typeMismatch(let type, let context) = decodingError else {
        XCTFail("Expected DecodingError.typeMismatch, got \(error)")
        return
      }
      
      XCTAssertTrue(type == JSONObject.self)
      XCTAssertEqual(context.debugDescription, "A presence should at least have a phx_ref.")
    }
  }
  
  func testPresenceV2DecodingEmptyMetas() {
    let jsonData = """
    {
      "metas": []
    }
    """.data(using: .utf8)!
    
    XCTAssertThrowsError(try JSONDecoder().decode(PresenceV2.self, from: jsonData)) { error in
      guard let decodingError = error as? DecodingError,
            case .typeMismatch(let type, let context) = decodingError else {
        XCTFail("Expected DecodingError.typeMismatch, got \(error)")
        return
      }
      
      XCTAssertTrue(type == JSONObject.self)
      XCTAssertEqual(context.debugDescription, "A presence should at least have a phx_ref.")
    }
  }
  
  func testPresenceV2DecodingMissingPhxRef() {
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
    
    XCTAssertThrowsError(try JSONDecoder().decode(PresenceV2.self, from: jsonData)) { error in
      guard let decodingError = error as? DecodingError,
            case .typeMismatch(let type, let context) = decodingError else {
        XCTFail("Expected DecodingError.typeMismatch, got \(error)")
        return
      }
      
      XCTAssertTrue(type == String.self)
      XCTAssertEqual(context.debugDescription, "A presence should at least have a phx_ref.")
    }
  }
  
  func testPresenceV2DecodingNonStringPhxRef() {
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
    
    XCTAssertThrowsError(try JSONDecoder().decode(PresenceV2.self, from: jsonData)) { error in
      guard let decodingError = error as? DecodingError,
            case .typeMismatch(let type, let context) = decodingError else {
        XCTFail("Expected DecodingError.typeMismatch, got \(error)")
        return
      }
      
      XCTAssertTrue(type == String.self)
      XCTAssertEqual(context.debugDescription, "A presence should at least have a phx_ref.")
    }
  }
  
  func testPresenceV2Encoding() throws {
    let state: JSONObject = [
      "user_id": .string("user_789"),
      "status": .string("online"),
      "count": .integer(42)
    ]
    let presence = PresenceV2(ref: "test_ref", state: state)
    
    let encodedData = try JSONEncoder().encode(presence)
    let decodedDict = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
    
    XCTAssertNotNil(decodedDict)
    XCTAssertEqual(decodedDict?["phx_ref"] as? String, "test_ref")
    
    let stateDict = decodedDict?["state"] as? [String: Any]
    XCTAssertNotNil(stateDict)
    XCTAssertEqual(stateDict?["user_id"] as? String, "user_789")
    XCTAssertEqual(stateDict?["status"] as? String, "online")
    XCTAssertEqual(stateDict?["count"] as? Int, 42)
  }
  
  // MARK: - PresenceV2 decodeState Tests
  
  struct TestUser: Codable, Equatable {
    let id: String
    let name: String
    let age: Int
  }
  
  func testDecodeStateSuccess() throws {
    let state: JSONObject = [
      "id": .string("user_123"),
      "name": .string("John Doe"),
      "age": .integer(30)
    ]
    let presence = PresenceV2(ref: "ref", state: state)
    
    let user = try presence.decodeState(as: TestUser.self)
    
    XCTAssertEqual(user.id, "user_123")
    XCTAssertEqual(user.name, "John Doe")
    XCTAssertEqual(user.age, 30)
  }
  
  func testDecodeStateWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase
    
    let state: JSONObject = [
      "user_id": .string("user_456"),
      "user_name": .string("Jane Doe"),
      "user_age": .integer(25)
    ]
    let presence = PresenceV2(ref: "ref", state: state)
    
    struct SnakeCaseUser: Codable, Equatable {
      let userId: String
      let userName: String
      let userAge: Int
    }
    
    let user = try presence.decodeState(as: SnakeCaseUser.self, decoder: customDecoder)
    
    XCTAssertEqual(user.userId, "user_456")
    XCTAssertEqual(user.userName, "Jane Doe")
    XCTAssertEqual(user.userAge, 25)
  }
  
  func testDecodeStateFailure() {
    let state: JSONObject = [
      "id": .string("user_123"),
      "name": .string("John Doe")
      // Missing required age field
    ]
    let presence = PresenceV2(ref: "ref", state: state)
    
    XCTAssertThrowsError(try presence.decodeState(as: TestUser.self))
  }
  
  // MARK: - PresenceAction Protocol Extension Tests
  
  struct MockPresenceAction: PresenceAction {
    let joins: [String: PresenceV2]
    let leaves: [String: PresenceV2]
    let rawMessage: RealtimeMessage
  }
  
  func testDecodeJoinsWithIgnoreOtherTypes() throws {
    let validState1: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25)
    ]
    let validState2: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      "age": .integer(30)
    ]
    let invalidState: JSONObject = [
      "id": .string("user_3"),
      "name": .string("Charlie")
      // Missing age field
    ]
    
    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState1),
      "key2": PresenceV2(ref: "ref2", state: validState2),
      "key3": PresenceV2(ref: "ref3", state: invalidState)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)
    
    // With ignoreOtherTypes = true (default), should return only valid users
    let users = try action.decodeJoins(as: TestUser.self)
    XCTAssertEqual(users.count, 2)
    XCTAssertTrue(users.contains(TestUser(id: "user_1", name: "Alice", age: 25)))
    XCTAssertTrue(users.contains(TestUser(id: "user_2", name: "Bob", age: 30)))
  }
  
  func testDecodeJoinsWithoutIgnoreOtherTypes() {
    let validState: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25)
    ]
    let invalidState: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob")
      // Missing age field
    ]
    
    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState),
      "key2": PresenceV2(ref: "ref2", state: invalidState)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)
    
    // With ignoreOtherTypes = false, should throw on invalid data
    XCTAssertThrowsError(try action.decodeJoins(as: TestUser.self, ignoreOtherTypes: false))
  }
  
  func testDecodeLeavesWithIgnoreOtherTypes() throws {
    let validState1: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25)
    ]
    let validState2: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob"),
      "age": .integer(30)
    ]
    let invalidState: JSONObject = [
      "id": .string("user_3"),
      "name": .string("Charlie")
      // Missing age field
    ]
    
    let leaves: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState1),
      "key2": PresenceV2(ref: "ref2", state: validState2),
      "key3": PresenceV2(ref: "ref3", state: invalidState)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: [:], leaves: leaves, rawMessage: rawMessage)
    
    // With ignoreOtherTypes = true (default), should return only valid users
    let users = try action.decodeLeaves(as: TestUser.self)
    XCTAssertEqual(users.count, 2)
    XCTAssertTrue(users.contains(TestUser(id: "user_1", name: "Alice", age: 25)))
    XCTAssertTrue(users.contains(TestUser(id: "user_2", name: "Bob", age: 30)))
  }
  
  func testDecodeLeavesWithoutIgnoreOtherTypes() {
    let validState: JSONObject = [
      "id": .string("user_1"),
      "name": .string("Alice"),
      "age": .integer(25)
    ]
    let invalidState: JSONObject = [
      "id": .string("user_2"),
      "name": .string("Bob")
      // Missing age field
    ]
    
    let leaves: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: validState),
      "key2": PresenceV2(ref: "ref2", state: invalidState)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: [:], leaves: leaves, rawMessage: rawMessage)
    
    // With ignoreOtherTypes = false, should throw on invalid data
    XCTAssertThrowsError(try action.decodeLeaves(as: TestUser.self, ignoreOtherTypes: false))
  }
  
  func testDecodeJoinsWithCustomDecoder() throws {
    let customDecoder = JSONDecoder()
    customDecoder.keyDecodingStrategy = .convertFromSnakeCase
    
    let state: JSONObject = [
      "user_id": .string("user_123"),
      "user_name": .string("Test User"),
      "user_age": .integer(28)
    ]
    
    let joins: [String: PresenceV2] = [
      "key1": PresenceV2(ref: "ref1", state: state)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)
    
    struct SnakeCaseUser: Codable, Equatable {
      let userId: String
      let userName: String
      let userAge: Int
    }
    
    let users = try action.decodeJoins(as: SnakeCaseUser.self, decoder: customDecoder)
    XCTAssertEqual(users.count, 1)
    XCTAssertEqual(users.first?.userId, "user_123")
    XCTAssertEqual(users.first?.userName, "Test User")
    XCTAssertEqual(users.first?.userAge, 28)
  }
  
  func testDecodeEmptyJoinsAndLeaves() throws {
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: [:], leaves: [:], rawMessage: rawMessage)
    
    let joinUsers = try action.decodeJoins(as: TestUser.self)
    let leaveUsers = try action.decodeLeaves(as: TestUser.self)
    
    XCTAssertEqual(joinUsers.count, 0)
    XCTAssertEqual(leaveUsers.count, 0)
  }
  
  // MARK: - PresenceActionImpl Tests
  
  func testPresenceActionImplInitialization() {
    let joins: [String: PresenceV2] = [
      "user1": PresenceV2(ref: "ref1", state: ["name": .string("User 1")])
    ]
    let leaves: [String: PresenceV2] = [
      "user2": PresenceV2(ref: "ref2", state: ["name": .string("User 2")])
    ]
    let rawMessage = RealtimeMessage(
      joinRef: "join_ref", ref: "ref", topic: "topic", event: "event", payload: ["key": .string("value")]
    )
    
    let impl = PresenceActionImpl(joins: joins, leaves: leaves, rawMessage: rawMessage)
    
    XCTAssertEqual(impl.joins.count, 1)
    XCTAssertEqual(impl.leaves.count, 1)
    XCTAssertEqual(impl.joins["user1"]?.ref, "ref1")
    XCTAssertEqual(impl.leaves["user2"]?.ref, "ref2")
    XCTAssertEqual(impl.rawMessage.topic, "topic")
    XCTAssertEqual(impl.rawMessage.event, "event")
  }
  
  func testPresenceActionImplConformsToProtocol() {
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let impl = PresenceActionImpl(joins: [:], leaves: [:], rawMessage: rawMessage)
    
    // Test that it can be used as PresenceAction
    let presenceAction: any PresenceAction = impl
    XCTAssertEqual(presenceAction.joins.count, 0)
    XCTAssertEqual(presenceAction.leaves.count, 0)
    XCTAssertEqual(presenceAction.rawMessage.topic, "test")
  }
  
  // MARK: - Edge Cases and Complex Scenarios
  
  func testPresenceV2WithComplexNestedState() throws {
    let complexState: JSONObject = [
      "user": .object([
        "id": .string("123"),
        "profile": .object([
          "name": .string("John"),
          "preferences": .object([
            "theme": .string("dark"),
            "notifications": .bool(true)
          ])
        ]),
        "tags": .array([.string("admin"), .string("developer")])
      ]),
      "metadata": .object([
        "last_seen": .string("2024-01-01T00:00:00Z"),
        "connection_count": .integer(3)
      ])
    ]
    
    let presence = PresenceV2(ref: "complex_ref", state: complexState)
    
    XCTAssertEqual(presence.ref, "complex_ref")
    XCTAssertEqual(presence.state["user"]?.objectValue?["id"]?.stringValue, "123")
    XCTAssertEqual(
      presence.state["user"]?.objectValue?["profile"]?.objectValue?["name"]?.stringValue,
      "John"
    )
    XCTAssertEqual(
      presence.state["user"]?.objectValue?["profile"]?.objectValue?["preferences"]?.objectValue?["theme"]?.stringValue,
      "dark"
    )
    XCTAssertEqual(presence.state["user"]?.objectValue?["tags"]?.arrayValue?.count, 2)
    XCTAssertEqual(presence.state["metadata"]?.objectValue?["connection_count"]?.intValue, 3)
  }
  
  func testPresenceV2RoundTripCoding() throws {
    let originalState: JSONObject = [
      "user_id": .string("user_789"),
      "status": .string("online"),
      "score": .double(98.5),
      "active": .bool(true),
      "tags": .array([.string("tag1"), .string("tag2")]),
      "metadata": .object(["key": .string("value")])
    ]
    let originalPresence = PresenceV2(ref: "original_ref", state: originalState)
    
    // Test that encoding works (we don't need the actual data for this test)
    _ = try JSONEncoder().encode(originalPresence)
    
    // Create the expected server format manually by adding the state to metas with phx_ref
    let stateWithRef = originalState.merging(["phx_ref": .string(originalPresence.ref)]) { _, new in new }
    let serverFormat: [String: Any] = [
      "metas": [
        stateWithRef.mapValues(\.value)
      ]
    ]
    
    let serverData = try JSONSerialization.data(withJSONObject: serverFormat)
    let decodedPresence = try JSONDecoder().decode(PresenceV2.self, from: serverData)
    
    XCTAssertEqual(decodedPresence.ref, originalPresence.ref)
    XCTAssertEqual(decodedPresence.state["user_id"]?.stringValue, "user_789")
    XCTAssertEqual(decodedPresence.state["status"]?.stringValue, "online")
    XCTAssertEqual(decodedPresence.state["score"]?.doubleValue, 98.5)
    XCTAssertEqual(decodedPresence.state["active"]?.boolValue, true)
    XCTAssertEqual(decodedPresence.state["tags"]?.arrayValue?.count, 2)
    XCTAssertNotNil(decodedPresence.state["metadata"]?.objectValue)
  }
  
  func testPresenceActionWithMixedValidAndInvalidData() throws {
    struct PartialUser: Codable {
      let id: String
      let name: String?
    }
    
    let validState: JSONObject = [
      "id": .string("valid_user"),
      "name": .string("Valid User")
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
      "invalid": PresenceV2(ref: "ref3", state: invalidState)
    ]
    
    let rawMessage = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "test", event: "test", payload: [:]
    )
    
    let action = MockPresenceAction(joins: joins, leaves: [:], rawMessage: rawMessage)
    
    // With ignoreOtherTypes = true, should get valid and partial users
    let users = try action.decodeJoins(as: PartialUser.self, ignoreOtherTypes: true)
    XCTAssertEqual(users.count, 2)
    
    let userIds = users.map(\.id).sorted()
    XCTAssertEqual(userIds, ["partial_user", "valid_user"])
  }
}