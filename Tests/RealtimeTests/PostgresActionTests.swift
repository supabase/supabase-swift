//
//  PostgresActionTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import XCTest

@testable import Realtime

final class PostgresActionTests: XCTestCase {
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

  func testColumnEquality() {
    let column1 = Column(name: "id", type: "int8")
    let column2 = Column(name: "id", type: "int8")
    let column3 = Column(name: "email", type: "text")

    XCTAssertEqual(column1, column2)
    XCTAssertNotEqual(column1, column3)
  }

  func testInsertActionEventType() {
    XCTAssertEqual(InsertAction.eventType, .insert)
  }

  func testInsertActionProperties() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John")]
    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    XCTAssertEqual(insertAction.columns, sampleColumns)
    XCTAssertEqual(insertAction.commitTimestamp, sampleDate)
    XCTAssertEqual(insertAction.record, record)
    XCTAssertEqual(insertAction.rawMessage.topic, "test:table")
  }

  func testUpdateActionEventType() {
    XCTAssertEqual(UpdateAction.eventType, .update)
  }

  func testUpdateActionProperties() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John Updated")]
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let updateAction = UpdateAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    XCTAssertEqual(updateAction.columns, sampleColumns)
    XCTAssertEqual(updateAction.commitTimestamp, sampleDate)
    XCTAssertEqual(updateAction.record, record)
    XCTAssertEqual(updateAction.oldRecord, oldRecord)
    XCTAssertEqual(updateAction.rawMessage.topic, "test:table")
  }

  func testDeleteActionEventType() {
    XCTAssertEqual(DeleteAction.eventType, .delete)
  }

  func testDeleteActionProperties() {
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let deleteAction = DeleteAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    XCTAssertEqual(deleteAction.columns, sampleColumns)
    XCTAssertEqual(deleteAction.commitTimestamp, sampleDate)
    XCTAssertEqual(deleteAction.oldRecord, oldRecord)
    XCTAssertEqual(deleteAction.rawMessage.topic, "test:table")
  }

  func testAnyActionEventType() {
    XCTAssertEqual(AnyAction.eventType, .all)
  }

  func testAnyActionInsertCase() {
    let record: JSONObject = ["id": .string("123"), "name": .string("John")]
    let insertAction = InsertAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      record: record,
      rawMessage: sampleMessage
    )

    let anyAction = AnyAction.insert(insertAction)
    XCTAssertEqual(anyAction.rawMessage.topic, "test:table")

    if case let .insert(wrappedAction) = anyAction {
      XCTAssertEqual(wrappedAction.record, record)
    } else {
      XCTFail("Expected insert case")
    }
  }

  func testAnyActionUpdateCase() {
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
    XCTAssertEqual(anyAction.rawMessage.topic, "test:table")

    if case let .update(wrappedAction) = anyAction {
      XCTAssertEqual(wrappedAction.record, record)
      XCTAssertEqual(wrappedAction.oldRecord, oldRecord)
    } else {
      XCTFail("Expected update case")
    }
  }

  func testAnyActionDeleteCase() {
    let oldRecord: JSONObject = ["id": .string("123"), "name": .string("John")]

    let deleteAction = DeleteAction(
      columns: sampleColumns,
      commitTimestamp: sampleDate,
      oldRecord: oldRecord,
      rawMessage: sampleMessage
    )

    let anyAction = AnyAction.delete(deleteAction)
    XCTAssertEqual(anyAction.rawMessage.topic, "test:table")

    if case let .delete(wrappedAction) = anyAction {
      XCTAssertEqual(wrappedAction.oldRecord, oldRecord)
    } else {
      XCTFail("Expected delete case")
    }
  }

  func testAnyActionEquality() {
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

    XCTAssertEqual(anyAction1, anyAction2)
  }

  func testDecodeRecord() throws {
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
    XCTAssertEqual(decodedRecord, expectedRecord)
  }

  func testDecodeOldRecord() throws {
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
    XCTAssertEqual(decodedOldRecord, expectedOldRecord)
  }

  func testDecodeRecordError() {
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
    XCTAssertThrowsError(try insertAction.decodeRecord(as: TestRecord.self, decoder: decoder))
  }
}
