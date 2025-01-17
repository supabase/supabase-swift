//
//  PostgresTransformsTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import InlineSnapshotTesting
import PostgREST
import XCTest

final class PostgrestTransformsTests: XCTestCase {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1")!,
      headers: [
        "apikey": DotEnv.SUPABASE_ANON_KEY
      ],
      logger: nil
    )
  )

  func testOrder() async throws {
    let res =
      try await client.from("users")
      .select()
      .order("username", ascending: false)
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)",
          "catchphrase" : "'cat' 'fat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "supabot"
        },
        {
          "age_range" : "[25,35)",
          "catchphrase" : "'bat' 'cat'",
          "data" : null,
          "status" : "OFFLINE",
          "username" : "kiwicopple"
        },
        {
          "age_range" : "[20,30)",
          "catchphrase" : "'json' 'test'",
          "data" : {
            "foo" : {
              "bar" : {
                "nested" : "value"
              },
              "baz" : "string value"
            }
          },
          "status" : "ONLINE",
          "username" : "jsonuser"
        },
        {
          "age_range" : "[20,30)",
          "catchphrase" : "'fat' 'rat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "dragarcia"
        },
        {
          "age_range" : "[25,35)",
          "catchphrase" : "'bat' 'rat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "awailas"
        }
      ]
      """
    }
  }

  func testOrderOnMultipleColumns() async throws {
    let res =
      try await client.from("messages")
      .select()
      .order("channel_id", ascending: false)
      .order("username", ascending: false)
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "channel_id" : 3,
          "data" : null,
          "id" : 4,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "id" : 2,
          "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "id" : 1,
          "message" : "Hello World 👋",
          "username" : "supabot"
        }
      ]
      """
    }
  }

  func testLimit() async throws {
    let res =
      try await client.from("users")
      .select()
      .limit(1)
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)",
          "catchphrase" : "'cat' 'fat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "supabot"
        }
      ]
      """
    }
  }

  func testRange() async throws {
    let res =
      try await client.from("users")
      .select()
      .range(from: 1, to: 3)
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[25,35)",
          "catchphrase" : "'bat' 'cat'",
          "data" : null,
          "status" : "OFFLINE",
          "username" : "kiwicopple"
        },
        {
          "age_range" : "[25,35)",
          "catchphrase" : "'bat' 'rat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "awailas"
        },
        {
          "age_range" : "[20,30)",
          "catchphrase" : "'fat' 'rat'",
          "data" : null,
          "status" : "ONLINE",
          "username" : "dragarcia"
        }
      ]
      """
    }
  }

  func testSingle() async throws {
    let res =
      try await client.from("users")
      .select()
      .limit(1)
      .single()
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      {
        "age_range" : "[1,2)",
        "catchphrase" : "'cat' 'fat'",
        "data" : null,
        "status" : "ONLINE",
        "username" : "supabot"
      }
      """
    }
  }

  func testSingleOnInsert() async throws {
    let res =
      try await client.from("users")
      .insert(["username": "foo"])
      .select()
      .single()
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      {
        "age_range" : null,
        "catchphrase" : null,
        "data" : null,
        "status" : "ONLINE",
        "username" : "foo"
      }
      """
    }

    try await client.from("users")
      .delete()
      .eq("username", value: "foo")
      .execute()
  }

  func testSelectOnInsert() async throws {
    let res =
      try await client.from("users")
      .insert(["username": "foo"])
      .select("status")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE"
        }
      ]
      """
    }

    try await client.from("users")
      .delete()
      .eq("username", value: "foo")
      .execute()
  }

  func testSelectOnRpc() async throws {
    let res =
      try await client.rpc("get_username_and_status", params: ["name_param": "supabot"])
      .select("status")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  func testRpcWithArray() async throws {
    struct Params: Encodable {
      let arr: [Int]
      let index: Int
    }
    let res =
      try await client.rpc("get_array_element", params: Params(arr: [37, 420, 64], index: 2))
      .execute().value as Int
    XCTAssertEqual(res, 420)
  }

  func testRpcWithReadOnlyAccessMode() async throws {
    struct Params: Encodable {
      let arr: [Int]
      let index: Int
    }
    let res =
      try await client.rpc(
        "get_array_element", params: Params(arr: [37, 420, 64], index: 2), get: true
      ).execute().value as Int
    XCTAssertEqual(res, 420)
  }

  func testCsv() async throws {
    let res = try await client.from("users").select().csv().execute().string()
    assertInlineSnapshot(of: res, as: .json) {
      #"""
      "username,data,age_range,status,catchphrase\nsupabot,,\"[1,2)\",ONLINE,\"'cat' 'fat'\"\nkiwicopple,,\"[25,35)\",OFFLINE,\"'bat' 'cat'\"\nawailas,,\"[25,35)\",ONLINE,\"'bat' 'rat'\"\ndragarcia,,\"[20,30)\",ONLINE,\"'fat' 'rat'\"\njsonuser,\"{\"\"foo\"\": {\"\"bar\"\": {\"\"nested\"\": \"\"value\"\"}, \"\"baz\"\": \"\"string value\"\"}}\",\"[20,30)\",ONLINE,\"'json' 'test'\""
      """#
    }
  }
}
