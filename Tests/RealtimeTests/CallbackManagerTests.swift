//
//  CallbackManagerTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import CustomDump
import Helpers
@testable import Realtime
import XCTest

final class CallbackManagerTests: XCTestCase {
  func testIntegration() {
    let callbackManager = CallbackManager()
    XCTAssertNoLeak(callbackManager)

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

    XCTAssertEqual(callbackManager.callbacks.count, 3)

    callbackManager.removeCallback(id: 2)
    callbackManager.removeCallback(id: 3)

    XCTAssertEqual(callbackManager.callbacks.count, 1)
    XCTAssertFalse(
      callbackManager.callbacks
        .contains(where: { $0.id == 2 || $0.id == 3 })
    )
  }

  func testSetServerChanges() {
    let callbackManager = CallbackManager()
    XCTAssertNoLeak(callbackManager)

    let changes = [PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: nil,
      id: 1
    )]

    callbackManager.setServerChanges(changes: changes)

    XCTAssertEqual(callbackManager.serverChanges, changes)
  }

  func testTriggerPostgresChanges() {
    let callbackManager = CallbackManager()
    XCTAssertNoLeak(callbackManager)

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

    let receivedActions = LockIsolated<[AnyAction]>([])
    let updateUsersId = callbackManager.addPostgresCallback(filter: updateUsersFilter) { action in
      receivedActions.withValue { $0.append(action) }
    }

    let insertUsersId = callbackManager.addPostgresCallback(filter: insertUsersFilter) { action in
      receivedActions.withValue { $0.append(action) }
    }

    let anyUsersId = callbackManager.addPostgresCallback(filter: anyUsersFilter) { action in
      receivedActions.withValue { $0.append(action) }
    }

    let deleteSpecificUserId = callbackManager
      .addPostgresCallback(filter: deleteSpecificUserFilter) { action in
        receivedActions.withValue { $0.append(action) }
      }

    let currentDate = Date()

    let updateUserAction = UpdateAction(
      columns: [],
      commitTimestamp: currentDate,
      record: ["email": .string("new@mail.com")],
      oldRecord: ["email": .string("old@mail.com")],
      rawMessage: RealtimeMessage(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
    )
    callbackManager.triggerPostgresChanges(ids: [updateUsersId], data: .update(updateUserAction))

    let insertUserAction = InsertAction(
      columns: [],
      commitTimestamp: currentDate,
      record: ["email": .string("email@mail.com")],
      rawMessage: RealtimeMessage(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
    )
    callbackManager.triggerPostgresChanges(ids: [insertUsersId], data: .insert(insertUserAction))

    let anyUserAction = AnyAction.insert(insertUserAction)
    callbackManager.triggerPostgresChanges(ids: [anyUsersId], data: anyUserAction)

    let deleteSpecificUserAction = DeleteAction(
      columns: [],
      commitTimestamp: currentDate,
      oldRecord: ["id": .string("1234")],
      rawMessage: RealtimeMessage(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
    )
    callbackManager.triggerPostgresChanges(
      ids: [deleteSpecificUserId],
      data: .delete(deleteSpecificUserAction)
    )

    expectNoDifference(
      receivedActions.value,
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

  func testTriggerBroadcast() throws {
    let callbackManager = CallbackManager()
    XCTAssertNoLeak(callbackManager)

    let event = "new_user"
    let message = RealtimeMessage(
      joinRef: nil,
      ref: nil,
      topic: "realtime:users",
      event: event,
      payload: ["email": "mail@example.com"]
    )

    let jsonObject = try JSONObject(message)

    let receivedMessage = LockIsolated<JSONObject?>(nil)
    callbackManager.addBroadcastCallback(event: event) {
      receivedMessage.setValue($0)
    }

    callbackManager.triggerBroadcast(event: event, json: jsonObject)

    XCTAssertEqual(receivedMessage.value, jsonObject)
  }

  func testTriggerPresenceDiffs() {
    let callbackManager = CallbackManager()

    let joins = ["user1": PresenceV2(ref: "ref", state: [:])]
    let leaves = ["user2": PresenceV2(ref: "ref", state: [:])]

    let receivedAction = LockIsolated(PresenceAction?.none)

    callbackManager.addPresenceCallback {
      receivedAction.setValue($0)
    }

    callbackManager.triggerPresenceDiffs(
      joins: joins,
      leaves: leaves,
      rawMessage: RealtimeMessage(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
    )

    expectNoDifference(receivedAction.value?.joins, joins)
    expectNoDifference(receivedAction.value?.leaves, leaves)
  }
}

extension XCTestCase {
  func XCTAssertNoLeak(_ object: AnyObject, file: StaticString = #file, line: UInt = #line) {
    addTeardownBlock { [weak object] in
      XCTAssertNil(object, file: file, line: line)
    }
  }
}
