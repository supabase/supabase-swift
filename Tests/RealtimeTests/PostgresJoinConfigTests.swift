//
//  PostgresJoinConfigTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import XCTest

@testable import Realtime

final class PostgresJoinConfigTests: XCTestCase {
  func testSameConfigButDifferentIdAreEqual() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertEqual(config1, config2)
  }

  func testSameConfigWithGlobEventAreEqual() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .all,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertEqual(config1, config2)
  }

  func testNonEqualConfig() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertNotEqual(config1, config2)
  }

  func testSameConfigButDifferentIdHaveEqualHash() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertEqual(config1.hashValue, config2.hashValue)
  }

  func testSameConfigWithGlobEventHaveDiffHash() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .all,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertNotEqual(config1.hashValue, config2.hashValue)
  }

  func testNonEqualConfigHaveDiffHash() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "users",
      filter: "id=1",
      id: 2
    )

    XCTAssertNotEqual(config1.hashValue, config2.hashValue)
  }

  func testConfigDifferingOnlyBySelectAreEqual() {
    let config1 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      select: ["id", "name"],
      id: 1
    )
    let config2 = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: "id=1",
      select: nil,
      id: 1
    )

    XCTAssertEqual(config1, config2)
    XCTAssertEqual(config1.hashValue, config2.hashValue)
  }

  func testSelectEncodesAsArray() throws {
    let config = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: nil,
      select: ["id", "first_name"],
      id: 1
    )

    let data = try JSONEncoder().encode(config)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertEqual(jsonObject?["select"] as? [String], ["id", "first_name"])
  }

  func testSelectOmittedWhenNil() throws {
    let config = PostgresJoinConfig(
      event: .insert,
      schema: "public",
      table: "users",
      filter: nil,
      select: nil,
      id: 1
    )

    let data = try JSONEncoder().encode(config)
    let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertNil(jsonObject?["select"])
  }
}
