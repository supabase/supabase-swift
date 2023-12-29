//
//  CallbackManagerTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import CustomDump
@testable import Realtime
import XCTest
@_spi(Internal) import _Helpers

final class CallbackManagerTests: XCTestCase {
  func testIntegration() {
    let callbackManager = CallbackManager()
    let filter = PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: nil,
      id: 1
    )

    XCTAssertEqual(
      callbackManager.addBroadcastCallback(event: "UPDATE") { _ in },
      1
    )

    XCTAssertEqual(
      callbackManager.addPostgresCallback(filter: filter) { _ in },
      2
    )

    XCTAssertEqual(callbackManager.addPresenceCallback { _ in }, 3)

    XCTAssertEqual(callbackManager.mutableState.value.callbacks.count, 3)

    callbackManager.removeCallback(id: 2)
    callbackManager.removeCallback(id: 3)

    XCTAssertEqual(callbackManager.mutableState.value.callbacks.count, 1)
    XCTAssertFalse(
      callbackManager.mutableState.value.callbacks
        .contains(where: { $0.id == 2 || $0.id == 3 })
    )
  }

  func testSetServerChanges() {
    let callbackManager = CallbackManager()
    let changes = [PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: nil,
      id: 1
    )]

    callbackManager.setServerChanges(changes: changes)

    XCTAssertEqual(callbackManager.mutableState.value.serverChanges, changes)
  }

  func testTriggerPostgresChanges() {
    let callbackManager = CallbackManager()
    let updateUsersFilter = PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: nil,
      id: 1
    )
    let insertUsersFilter = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: nil,
      id: 2
    )
    let anyUsersFilter = PostgresJoinConfig(
      event: .all,
      schema: "public",
      table: "users",
      filter: nil,
      id: 3
    )
    let deleteSpecificUserFilter = PostgresJoinConfig(
      event: .delete,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 4
    )

    callbackManager.setServerChanges(changes: [
      updateUsersFilter,
      insertUsersFilter,
      anyUsersFilter,
      deleteSpecificUserFilter,
    ])

    var receivedActions: [AnyAction] = []
    let updateUsersId = callbackManager.addPostgresCallback(filter: updateUsersFilter) { action in
      receivedActions.append(action)
    }

    let insertUsersId = callbackManager.addPostgresCallback(filter: insertUsersFilter) { action in
      receivedActions.append(action)
    }

    let anyUsersId = callbackManager.addPostgresCallback(filter: anyUsersFilter) { action in
      receivedActions.append(action)
    }

    let deleteSpecificUserId = callbackManager
      .addPostgresCallback(filter: deleteSpecificUserFilter) { action in
        receivedActions.append(action)
      }

    let currentDate = Date()

    let updateUserAction = UpdateAction(
      columns: [],
      commitTimestamp: currentDate,
      record: ["email": .string("new@mail.com")],
      oldRecord: ["email": .string("old@mail.com")]
    )
    callbackManager.triggerPostgresChanges(ids: [updateUsersId], data: .update(updateUserAction))

    let insertUserAction = InsertAction(
      columns: [],
      commitTimestamp: currentDate,
      record: ["email": .string("email@mail.com")]
    )
    callbackManager.triggerPostgresChanges(ids: [insertUsersId], data: .insert(insertUserAction))

    let anyUserAction = AnyAction.insert(insertUserAction)
    callbackManager.triggerPostgresChanges(ids: [anyUsersId], data: anyUserAction)

    let deleteSpecificUserAction = DeleteAction(
      columns: [],
      commitTimestamp: currentDate,
      oldRecord: ["id": .string("1234")]
    )
    callbackManager.triggerPostgresChanges(
      ids: [deleteSpecificUserId],
      data: .delete(deleteSpecificUserAction)
    )

    XCTAssertNoDifference(
      receivedActions,
      [
        .update(updateUserAction),
        anyUserAction,
        .insert(insertUserAction),
        anyUserAction,
        .insert(insertUserAction),
        .delete(deleteSpecificUserAction),
      ]
    )
  }

  func testTriggerBroadcast() {
    let callbackManager = CallbackManager()
    let event = "new_user"
    let json = AnyJSON.object(["email": .string("example@mail.com")])

    var receivedJSON: AnyJSON?
    callbackManager.addBroadcastCallback(event: event) {
      receivedJSON = $0
    }

    callbackManager.triggerBroadcast(event: event, json: json)

    XCTAssertEqual(receivedJSON, json)
  }

  func testTriggerPresenceDiffs() {
    let socket = RealtimeClient("/socket")
    let channel = RealtimeChannel(topic: "room", socket: socket)

    let callbackManager = CallbackManager()

    let joins = ["user1": Presence(channel: channel)]
    let leaves = ["user2": Presence(channel: channel)]

    var receivedAction: PresenceAction?

    callbackManager.addPresenceCallback {
      receivedAction = $0
    }

    callbackManager.triggerPresenceDiffs(joins: joins, leaves: leaves)

    XCTAssertIdentical(receivedAction?.joins["user1"], joins["user1"])
    XCTAssertIdentical(receivedAction?.leaves["user2"], leaves["user2"])

    XCTAssertEqual(receivedAction?.joins.count, 1)
    XCTAssertEqual(receivedAction?.leaves.count, 1)
  }
}
