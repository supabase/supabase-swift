//
//  PostgrestResourceEmbeddingTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import InlineSnapshotTesting
import PostgREST
import XCTest

final class PostgrestResourceEmbeddingTests: XCTestCase {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1")!,
      headers: [
        "apikey": DotEnv.SUPABASE_ANON_KEY,
      ],
      logger: nil
    )
  )

  func testEmbeddedSelect() async throws {
    let res = try await client.from("users").select("messages(*)").execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
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
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedEq() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .eq("messages.channel_id", value: 1)
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
            {
              "channel_id" : 1,
              "data" : null,
              "id" : 1,
              "message" : "Hello World 👋",
              "username" : "supabot"
            }
          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedOr() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .or("channel_id.eq.2,message.eq.Hello World 👋", referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
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
            }
          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedOrWithAnd() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .or("channel_id.eq.2,and(message.eq.Hello World 👋,username.eq.supabot)", referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
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
            }
          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedOrder() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .order("channel_id", ascending: false, referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
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
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedOrderOnMultipleColumns() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .order("channel_id", ascending: false, referencedTable: "messages")
      .order("username", ascending: false, referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
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
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedLimit() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .limit(1, referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
            {
              "channel_id" : 1,
              "data" : null,
              "id" : 1,
              "message" : "Hello World 👋",
              "username" : "supabot"
            }
          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }

  func testEmbeddedRange() async throws {
    let res = try await client.from("users")
      .select("messages(*)")
      .range(from: 1, to: 1, referencedTable: "messages")
      .execute().value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "messages" : [
            {
              "channel_id" : 2,
              "data" : null,
              "id" : 2,
              "message" : "Perfection is attained, not when there is nothing more to add, but when there is nothing left to take away.",
              "username" : "supabot"
            }
          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        },
        {
          "messages" : [

          ]
        }
      ]
      """
    }
  }
}
