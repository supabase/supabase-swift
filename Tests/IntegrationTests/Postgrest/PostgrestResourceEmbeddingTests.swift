//
//  PostgrestResourceEmbeddingTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import InlineSnapshotTesting
import PostgREST
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestResourceEmbeddingTests {
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
  func embeddedSelect() async throws {
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedEq() async throws {
    let res =
      try await client.from("users")
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedOr() async throws {
    let res =
      try await client.from("users")
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedOrWithAnd() async throws {
    let res =
      try await client.from("users")
      .select("messages(*)")
      .or(
        "channel_id.eq.2,and(message.eq.Hello World 👋,username.eq.supabot)",
        referencedTable: "messages"
      )
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedOrder() async throws {
    let res =
      try await client.from("users")
      .select("messages(*)")
      .order("channel_id", ascending: false, referencedTable: "messages")
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedOrderOnMultipleColumns() async throws {
    let res =
      try await client.from("users")
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedLimit() async throws {
    let res =
      try await client.from("users")
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
        }
      ]
      """
    }
  }

  @Test
  func embeddedRange() async throws {
    let res =
      try await client.from("users")
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
        }
      ]
      """
    }
  }
}
