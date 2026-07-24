//
//  CallbackManagerTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct CallbackManagerTests {
  @Test
  func integration() {
    weak var weakCallbackManager: CallbackManager?

    do {
      let callbackManager = CallbackManager()
      weakCallbackManager = callbackManager

      let filter = PostgresJoinConfig(
        event: .update,
        schema: "public",
        table: "users",
        filter: nil,
        id: 1
      )

      #expect(
        callbackManager.addBroadcastCallback(event: "UPDATE") { _ in } == 1
      )

      #expect(
        callbackManager.addPostgresCallback(filter: filter) { _ in } == 2
      )

      #expect(callbackManager.addPresenceCallback { _ in } == 3)

      #expect(callbackManager.callbacks.count == 3)

      callbackManager.removeCallback(id: 2)
      callbackManager.removeCallback(id: 3)

      #expect(callbackManager.callbacks.count == 1)
      #expect(
        !callbackManager.callbacks
          .contains(where: { $0.id == 2 || $0.id == 3 })
      )
    }

    #expect(weakCallbackManager == nil)
  }

  @Test
  func setServerChanges() {
    weak var weakCallbackManager: CallbackManager?

    do {
      let callbackManager = CallbackManager()
      weakCallbackManager = callbackManager

      let changes = [
        PostgresJoinConfig(
          event: .update,
          schema: "public",
          table: "users",
          filter: nil,
          id: 1
        )
      ]

      callbackManager.setServerChanges(changes: changes)

      #expect(callbackManager.serverChanges == changes)
    }

    #expect(weakCallbackManager == nil)
  }

  @Test
  func triggerPostgresChanges() {
    weak var weakCallbackManager: CallbackManager?

    do {
      let callbackManager = CallbackManager()
      weakCallbackManager = callbackManager

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
      let updateUsersId = callbackManager.addPostgresCallback(filter: updateUsersFilter) {
        action in
        receivedActions.withValue { $0.append(action) }
      }

      let insertUsersId = callbackManager.addPostgresCallback(filter: insertUsersFilter) {
        action in
        receivedActions.withValue { $0.append(action) }
      }

      let anyUsersId = callbackManager.addPostgresCallback(filter: anyUsersFilter) { action in
        receivedActions.withValue { $0.append(action) }
      }

      let deleteSpecificUserId =
        callbackManager
        .addPostgresCallback(filter: deleteSpecificUserFilter) { action in
          receivedActions.withValue { $0.append(action) }
        }

      let currentDate = Date()

      let updateUserAction = UpdateAction(
        columns: [],
        commitTimestamp: currentDate,
        record: ["email": .string("new@mail.com")],
        oldRecord: ["email": .string("old@mail.com")],
        rawMessage: RealtimeMessageV2(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
      )
      callbackManager.triggerPostgresChanges(ids: [updateUsersId], data: .update(updateUserAction))

      let insertUserAction = InsertAction(
        columns: [],
        commitTimestamp: currentDate,
        record: ["email": .string("email@mail.com")],
        rawMessage: RealtimeMessageV2(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
      )
      callbackManager.triggerPostgresChanges(ids: [insertUsersId], data: .insert(insertUserAction))

      let anyUserAction = AnyAction.insert(insertUserAction)
      callbackManager.triggerPostgresChanges(ids: [anyUsersId], data: anyUserAction)

      let deleteSpecificUserAction = DeleteAction(
        columns: [],
        commitTimestamp: currentDate,
        oldRecord: ["id": .string("1234")],
        rawMessage: RealtimeMessageV2(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
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

    #expect(weakCallbackManager == nil)
  }

  @Test
  func triggerBroadcast() throws {
    weak var weakCallbackManager: CallbackManager?

    do {
      let callbackManager = CallbackManager()
      weakCallbackManager = callbackManager

      let event = "new_user"
      let message = RealtimeMessageV2(
        joinRef: nil,
        ref: nil,
        topic: "realtime:users",
        event: event,
        payload: ["email": "mail@example.com"]
      )

      let jsonObject = try JSONObject(message)

      // Match exact event
      let receivedMessage = LockIsolated<JSONObject?>(nil)
      callbackManager.addBroadcastCallback(event: event) {
        receivedMessage.setValue($0)
      }
      callbackManager.triggerBroadcast(event: event, json: jsonObject)
      #expect(receivedMessage.value == jsonObject)

      // Match event case-insensitive
      let caseInsensitiveMessage = LockIsolated<JSONObject?>(nil)
      callbackManager.addBroadcastCallback(event: event) {
        caseInsensitiveMessage.setValue($0)
      }
      callbackManager.triggerBroadcast(event: "NEW_USER", json: jsonObject)
      #expect(caseInsensitiveMessage.value == jsonObject)

      // Match any events with wildcard
      let wildcardReceivedMessage = LockIsolated<JSONObject?>(nil)
      callbackManager.addBroadcastCallback(event: "*") {
        wildcardReceivedMessage.setValue($0)
      }
      callbackManager.triggerBroadcast(event: event, json: jsonObject)
      #expect(wildcardReceivedMessage.value == jsonObject)
    }

    #expect(weakCallbackManager == nil)
  }

  @Test
  func triggerPresenceDiffs() {
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
      rawMessage: RealtimeMessageV2(joinRef: nil, ref: nil, topic: "", event: "", payload: [:])
    )

    expectNoDifference(receivedAction.value?.joins, joins)
    expectNoDifference(receivedAction.value?.leaves, leaves)
  }

  @Test
  func triggerSystem() {
    let callbackManager = CallbackManager()

    let receivedMessage = LockIsolated(RealtimeMessageV2?.none)
    callbackManager.addSystemCallback { message in
      receivedMessage.setValue(message)
    }

    callbackManager.triggerSystem(
      message: RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "test", event: "system", payload: ["status": "ok"]))

    #expect(receivedMessage.value?._eventType == .system)
    #expect(receivedMessage.value?.status == .ok)
  }
}
