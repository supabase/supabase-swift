//
//  PostgresTransformsTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

// cspell:ignore nsupabot nkiwicopple nawailas ndragarcia
import Foundation
import InlineSnapshotTesting
import PostgREST
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestTransformsTests {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1")!,
      headers: [
        "apikey": DotEnv.SUPABASE_PUBLISHABLE_KEY
      ],
      logger: nil
    )
  )

  init() async throws {
    // Clean up test data before running tests.
    // Delete users with email (test data), preserving seed data (users with username only).
    try await client.from("users").delete().not("email", operator: .is, value: AnyJSON.null)
      .execute()
  }

  @Test
  func order() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
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

  @Test
  func orderOnMultipleColumns() async throws {
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

  @Test
  func limit() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
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

  @Test
  func range() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
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

  @Test
  func single() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
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

  @Test
  func maybeSingle() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
      .eq("username", value: "supabot")
      .maybeSingle()
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

  @Test
  func maybeSingleReturnsNilOnZeroRows() async throws {
    let res: AnyJSON? =
      try await client.from("users")
      .select("username")
      .eq("username", value: "does-not-exist")
      .maybeSingle()
      .execute().value

    #expect(res == nil)
  }

  @Test
  func dryRunOnUpdate() async throws {
    // Requires `pgrst.db_tx_end = 'commit-allow-override'` on the `authenticator` role
    // (see migrations/20240101000000_initial_schema.sql) so `Prefer: tx=rollback` is honored.
    try await client.from("users").insert([
      "username": "dry-run-scratch", "email": "dry-run-scratch@example.com",
    ])
    .execute()

    _ = try await client.from("users")
      .update(["catchphrase": "temporary"])
      .eq("username", value: "dry-run-scratch")
      .dryRun()
      .execute()

    let after =
      try await client.from("users")
      .select("catchphrase")
      .eq("username", value: "dry-run-scratch")
      .single()
      .execute().value as AnyJSON

    assertInlineSnapshot(of: after, as: .json) {
      """
      {
        "catchphrase" : null
      }
      """
    }
  }

  @Test
  func singleOnInsert() async throws {
    let res =
      try await client.from("users")
      .insert(["username": "foo"])
      .select("age_range,catchphrase,data,status,username")
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

  @Test
  func selectOnInsert() async throws {
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

  @Test
  func selectOnRpc() async throws {
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

  @Test
  func rpcWithArray() async throws {
    struct Params: Encodable {
      let arr: [Int]
      let index: Int
    }
    let res =
      try await client.rpc("get_array_element", params: Params(arr: [37, 420, 64], index: 2))
      .execute().value as Int
    #expect(res == 420)
  }

  @Test
  func rpcWithReadOnlyAccessMode() async throws {
    struct Params: Encodable {
      let arr: [Int]
      let index: Int
    }
    let res =
      try await client.rpc(
        "get_array_element", params: Params(arr: [37, 420, 64], index: 2), get: true
      ).execute().value as Int
    #expect(res == 420)
  }

  @Test
  func csv() async throws {
    let res = try await client.from("users").select("username,data,age_range,status,catchphrase")
      .csv().execute().string()
    assertInlineSnapshot(of: res, as: .json) {
      #"""
      "username,data,age_range,status,catchphrase\nsupabot,,\"[1,2)\",ONLINE,\"'cat' 'fat'\"\nkiwicopple,,\"[25,35)\",OFFLINE,\"'bat' 'cat'\"\nawailas,,\"[25,35)\",ONLINE,\"'bat' 'rat'\"\ndragarcia,,\"[20,30)\",ONLINE,\"'fat' 'rat'\""
      """#
    }
  }
}
