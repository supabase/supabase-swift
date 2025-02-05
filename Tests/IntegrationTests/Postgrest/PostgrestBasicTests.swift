//
//  PostgrestBasicTests.swift
//
//
//  Created by Guilherme Souza on 06/05/24.
//

import InlineSnapshotTesting
import PostgREST
import XCTest

final class PostgrestBasicTests: XCTestCase {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1")!,
      headers: [
        "apikey": DotEnv.SUPABASE_ANON_KEY,
      ],
      logger: nil
    )
  )

  func testBasicSelectTable() async throws {
    let response = try await client.from("users").select().execute().value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
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
        }
      ]
      """
    }
  }

  func testBasicSelectView() async throws {
    let response = try await client.from("updatable_view").select().execute().value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "non_updatable_column" : 1,
          "username" : "supabot"
        },
        {
          "non_updatable_column" : 1,
          "username" : "kiwicopple"
        },
        {
          "non_updatable_column" : 1,
          "username" : "awailas"
        },
        {
          "non_updatable_column" : 1,
          "username" : "dragarcia"
        },
        {
          "non_updatable_column" : 1,
          "username" : "jsonuser"
        }
      ]
      """
    }
  }

  func testRPC() async throws {
    let response = try await client.rpc("get_status", params: ["name_param": "supabot"]).execute().value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
      """
      "ONLINE"
      """
    }
  }

  func testRPCReturnsVoid() async throws {
    let response = try await client.rpc("void_func").execute().data
    XCTAssertEqual(response, Data())
  }

  func testIgnoreDuplicates_upsert() async throws {
    let response = try await client.from("users")
      .upsert(["username": "dragarcia"], onConflict: "username", ignoreDuplicates: true)
      .select().execute().value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
      """
      [

      ]
      """
    }
  }

  func testBasicInsertUpdateAndDelete() async throws {
    // Basic insert
    var response = try await client.from("messages")
      .insert(AnyJSON.object(["message": "foo", "username": "supabot", "channel_id": 1]))
      .select("channel_id,data,message,username")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    response = try await client.from("messages").select("channel_id,data,message,username").execute().value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "Hello World 👋",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
          "username" : "supabot"
        },
        {
          "channel_id" : 3,
          "data" : null,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    // Upsert

    response = try await client.from("messages")
      .upsert(
        AnyJSON.object(
          [
            "id": 3,
            "message": "foo",
            "username": "supabot",
            "channel_id": 2,
          ]
        )
      )
      .select("channel_id,data,message,username")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    response = try await client.from("messages").select("channel_id,data,message,username").execute().value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "Hello World 👋",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
          "username" : "supabot"
        },
        {
          "channel_id" : 3,
          "data" : null,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    // Bulk insert

    response = try await client.from("messages")
      .insert(
        AnyJSON.array([
          ["message": "foo", "username": "supabot", "channel_id": 1],
          ["message": "foo", "username": "supabot", "channel_id": 1],
        ])
      )
      .select("channel_id,data,message,username")
      .execute()
      .value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    response = try await client.from("messages").select("channel_id,data,message,username").execute().value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "Hello World 👋",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
          "username" : "supabot"
        },
        {
          "channel_id" : 3,
          "data" : null,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    // Basic update
    response = try await client.from("messages")
      .update(["channel_id": 2])
      .eq("message", value: "foo")
      .select("channel_id,data,message,username")
      .execute()
      .value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    response = try await client.from("messages").select("channel_id,data,message,username").execute().value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "message" : "Hello World 👋",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
          "username" : "supabot"
        },
        {
          "channel_id" : 3,
          "data" : null,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    // Basic delete
    response = try await client.from("messages")
      .delete()
      .eq("message", value: "foo")
      .select("channel_id,data,message,username")
      .execute()
      .value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        },
        {
          "channel_id" : 2,
          "data" : null,
          "message" : "foo",
          "username" : "supabot"
        }
      ]
      """
    }

    response = try await client.from("messages").select().execute().value
    assertInlineSnapshot(of: response, as: .json) {
      """
      [
        {
          "channel_id" : 1,
          "data" : null,
          "id" : 1,
          "message" : "Hello World 👋",
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
          "channel_id" : 3,
          "data" : null,
          "id" : 4,
          "message" : "Some message on channel wihtout details",
          "username" : "supabot"
        }
      ]
      """
    }
  }
}
