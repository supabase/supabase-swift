//
//  PostgresActionTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct PostgresActionTests {
  private let sampleMessage = RealtimeMessageV2(
    joinRef: nil,
    ref: nil,
    topic: "test:table",
    event: "postgres_changes",
    payload: [:]
  )

  private let sampleColumns = [
    Column(name: "id", type: "int8"),
    Column(name: "name", type: "text"),
    Column(name: "email", type: "text"),
  ]

  private let sampleDate = Date(timeIntervalSince1970: 1_722_246_000)  // Fixed timestamp for consistency

  @Test
  func columnEquality() {
    let column1 = Column(name: "id", type: "int8")
    let column2 = Column(name: "id", type: "int8")
    let column3 = Column(name: "email", type: "text")

    #expect(column1 == column2)
    #expect(column1 != column3)
  }

  @Test
  func insertActionEventType() {
    #expect(InsertAction.eventType == .insert)
  }

  @Test
  func insertActionProperties() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John")]
    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    #expect(insertAction.columns == sampleColumns)
    #expect(insertAction.commitTimestamp == sampleDate)
    #expect(insertAction.record == record)
    #expect(insertAction.rawMessage.topic == "test:table")
  }

  @Test
  func updateActionEventType() {
    #expect(UpdateAction.eventType == .update)
  }

  @Test
  func updateActionProperties() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John Updated")]
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let updateAction = UpdateAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    #expect(updateAction.columns == sampleColumns)
    #expect(updateAction.commitTimestamp == sampleDate)
    #expect(updateAction.record == record)
    #expect(updateAction.oldRecord == oldRecord)
    #expect(updateAction.rawMessage.topic == "test:table")
  }

  @Test
  func deleteActionEventType() {
    #expect(DeleteAction.eventType == .delete)
  }

  @Test
  func deleteActionProperties() {
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let deleteAction = DeleteAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    #expect(deleteAction.columns == sampleColumns)
    #expect(deleteAction.commitTimestamp == sampleDate)
    #expect(deleteAction.oldRecord == oldRecord)
    #expect(deleteAction.rawMessage.topic == "test:table")
  }

  @Test
  func anyActionEventType() {
    #expect(AnyAction.eventType == .all)
  }

  @Test
  func anyActionInsertCase() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John")]
    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    let anyAction = AnyAction.insert(insertAction)
    #expect(anyAction.rawMessage.topic == "test:table")

    if case .insert(let wrappedAction) = anyAction {
      #expect(wrappedAction.record == record)
    } else {
      Issue.record("Expected insert case")
    }
  }

  @Test
  func anyActionUpdateCase() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John Updated")]
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let updateAction = UpdateAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    let anyAction = AnyAction.update(updateAction)
    #expect(anyAction.rawMessage.topic == "test:table")

    if case .update(let wrappedAction) = anyAction {
      #expect(wrappedAction.record == record)
      #expect(wrappedAction.oldRecord == oldRecord)
    } else {
      Issue.record("Expected update case")
    }
  }

  @Test
  func anyActionDeleteCase() {
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let deleteAction = DeleteAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    let anyAction = AnyAction.delete(deleteAction)
    #expect(anyAction.rawMessage.topic == "test:table")

    if case .delete(let wrappedAction) = anyAction {
      #expect(wrappedAction.oldRecord == oldRecord)
    } else {
      Issue.record("Expected delete case")
    }
  }

  @Test
  func anyActionEquality() {
    let record: JSONObject = ["id": .string("123")]
    let insertAction1 = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )
    let insertAction2 = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    let anyAction1 = AnyAction.insert(insertAction1)
    let anyAction2 = AnyAction.insert(insertAction2)

    #expect(anyAction1 == anyAction2)
  }

  @Test
  func decodeRecord() throws {
    struct TestRecord: Codable, Equatable {
      let id: String
      let name: String
      let email: String?
    }

    let record: JSONObject = [
      "id": .string("123"),
      "name": .string("John"),
      "email": .string("john@example.com"),
    ]

    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    let decoder = JSONDecoder()
    let decodedRecord = try insertAction.decodeRecord(as: TestRecord.self, decoder: decoder)

    let expectedRecord = TestRecord(id: "123", name: "John", email: "john@example.com")
    #expect(decodedRecord == expectedRecord)
  }

  @Test
  func decodeOldRecord() throws {
    struct TestRecord: Codable, Equatable {
      let id: String
      let name: String
    }

    let record: JSONObject = ["id": .string("123"), "name": .string("John Updated")]
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let updateAction = UpdateAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    let decoder = JSONDecoder()
    let decodedOldRecord = try updateAction.decodeOldRecord(as: TestRecord.self, decoder: decoder)

    let expectedOldRecord = TestRecord(id: "123", name: "John")
    #expect(decodedOldRecord == expectedOldRecord)
  }

  @Test
  func decodeRecordError() {
    struct TestRecord: Codable {
      let id: Int  // This will cause decode error since we're passing string
      let name: String
    }

    let record: JSONObject = [
      "id": .string("not-a-number"),  // This should cause decoding to fail
      "name": .string("John"),
    ]

    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    let decoder = JSONDecoder()
    #expect(throws: (any Error).self) {
      try insertAction.decodeRecord(as: TestRecord.self, decoder: decoder)
    }
  }
}
