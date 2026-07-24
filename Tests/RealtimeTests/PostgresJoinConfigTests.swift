//
//  PostgresJoinConfigTests.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct PostgresJoinConfigTests {
  @Test
  func sameConfigButDifferentIdAreEqual() {
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

    #expect(config1 == config2)
  }

  @Test
  func sameConfigWithGlobEventAreEqual() {
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

    #expect(config1 == config2)
  }

  @Test
  func nonEqualConfig() {
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

    #expect(config1 != config2)
  }

  @Test
  func sameConfigButDifferentIdHaveEqualHash() {
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

    #expect(config1.hashValue == config2.hashValue)
  }

  @Test
  func sameConfigWithGlobEventHaveDiffHash() {
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

    #expect(config1.hashValue != config2.hashValue)
  }

  @Test
  func nonEqualConfigHaveDiffHash() {
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

    #expect(config1.hashValue != config2.hashValue)
  }

  @Test
  func configDifferingOnlyBySelectAreEqual() {
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

    #expect(config1 == config2)
    #expect(config1.hashValue == config2.hashValue)
  }

  @Test
  func selectEncodesAsArray() throws {
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

    #expect(jsonObject?["select"] as? [String] == ["id", "first_name"])
  }

  @Test
  func selectOmittedWhenNil() throws {
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

    #expect(jsonObject?["select"] == nil)
  }
}
