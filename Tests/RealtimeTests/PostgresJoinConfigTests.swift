//
//  PostgresJoinConfigTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

@testable import Realtime
import XCTest

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
}
