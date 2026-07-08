//
//  PostgrestFilterTests.swift
//
//
//  Created by Guilherme Souza on 06/05/24.
//

import Foundation
import InlineSnapshotTesting
import PostgREST
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestFilterTests {
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
  func not() async throws {
    let res =
      try await client.from("users")
      .select("status")
      .not("status", operator: .eq, value: "OFFLINE")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE"
        },
        {
          "status" : "ONLINE"
        },
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  @Test
  func or() async throws {
    let res =
      try await client.from("users")
      .select("status,username")
      .or("status.eq.OFFLINE,username.eq.supabot")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE",
          "username" : "supabot"
        },
        {
          "status" : "OFFLINE",
          "username" : "kiwicopple"
        }
      ]
      """
    }
  }

  @Test
  func eq() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .eq("username", value: "supabot")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func neq() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .neq("username", value: "supabot")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "kiwicopple"
        },
        {
          "username" : "awailas"
        },
        {
          "username" : "dragarcia"
        }
      ]
      """
    }
  }

  @Test
  func gt() async throws {
    let res =
      try await client.from("messages")
      .select("id")
      .gt("id", value: 1)
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "id" : 2
        }
      ]
      """
    }
  }

  @Test
  func gte() async throws {
    let res =
      try await client.from("messages")
      .select("id")
      .gte("id", value: 1)
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "id" : 1
        },
        {
          "id" : 2
        }
      ]
      """
    }
  }

  @Test
  func le() async throws {
    let res =
      try await client.from("messages")
      .select("id")
      .lt("id", value: 2)
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "id" : 1
        }
      ]
      """
    }
  }

  @Test
  func lte() async throws {
    let res =
      try await client.from("messages")
      .select("id")
      .lte("id", value: 2)
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "id" : 1
        },
        {
          "id" : 2
        }
      ]
      """
    }
  }

  @Test
  func like() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .like("username", pattern: "%supa%")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func likeAllOf() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .likeAllOf("username", patterns: ["%supa%", "%bot%"])
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func likeAnyOf() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .likeAnyOf("username", patterns: ["%supa%", "%kiwi%"])
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        },
        {
          "username" : "kiwicopple"
        }
      ]
      """
    }
  }

  @Test
  func ilike() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .ilike("username", pattern: "%SUPA%")
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func ilikeAllOf() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .iLikeAllOf("username", patterns: ["%SUPA%", "%bot%"])
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func ilikeAnyOf() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .iLikeAnyOf("username", patterns: ["%supa%", "%KIWI%"])
      .execute()
      .value as AnyJSON
    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        },
        {
          "username" : "kiwicopple"
        }
      ]
      """
    }
  }

  @Test
  func `is`() async throws {
    let res =
      try await client.from("users").select("data").is("data", value: nil)
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "data" : null
        },
        {
          "data" : null
        },
        {
          "data" : null
        },
        {
          "data" : null
        }
      ]
      """
    }
  }

  @Test
  func `in`() async throws {
    let statuses = ["ONLINE", "OFFLINE"]
    let res =
      try await client.from("users").select("status").in("status", values: statuses)
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE"
        },
        {
          "status" : "OFFLINE"
        },
        {
          "status" : "ONLINE"
        },
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  @Test
  func notIn() async throws {
    let res =
      try await client.from("users").select("status").notIn("status", values: ["OFFLINE"])
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE"
        },
        {
          "status" : "ONLINE"
        },
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  @Test
  func contains() async throws {
    let res =
      try await client.from("users").select("age_range").contains("age_range", value: "[1,2)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)"
        }
      ]
      """
    }
  }

  @Test
  func containedBy() async throws {
    let res =
      try await client.from("users").select("age_range").containedBy("age_range", value: "[1,2)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)"
        }
      ]
      """
    }
  }

  @Test
  func rangeLt() async throws {
    let res =
      try await client.from("users").select("age_range").rangeLt("age_range", range: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)"
        }
      ]
      """
    }
  }

  @Test
  func rangeGt() async throws {
    let res =
      try await client.from("users").select("age_range").rangeGt("age_range", range: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[25,35)"
        },
        {
          "age_range" : "[25,35)"
        }
      ]
      """
    }
  }

  @Test
  func rangeLte() async throws {
    let res =
      try await client.from("users").select("age_range").rangeLte("age_range", range: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)"
        }
      ]
      """
    }
  }

  @Test
  func rangeGte() async throws {
    let res =
      try await client.from("users").select("age_range").rangeGte("age_range", range: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[25,35)"
        },
        {
          "age_range" : "[25,35)"
        },
        {
          "age_range" : "[20,30)"
        }
      ]
      """
    }
  }

  @Test
  func rangeAdjacent() async throws {
    let res =
      try await client.from("users").select("age_range").rangeAdjacent("age_range", range: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[1,2)"
        },
        {
          "age_range" : "[25,35)"
        },
        {
          "age_range" : "[25,35)"
        }
      ]
      """
    }
  }

  @Test
  func overlaps() async throws {
    let res =
      try await client.from("users").select("age_range").overlaps("age_range", value: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[20,30)"
        }
      ]
      """
    }
  }

  @Test
  func textSearch() async throws {
    let res =
      try await client.from("users").select("catchphrase")
      .textSearch("catchphrase", query: "'fat' & 'cat'", config: "english")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "catchphrase" : "'cat' 'fat'"
        }
      ]
      """
    }
  }

  @Test
  func textSearchWithPlain() async throws {
    let res =
      try await client.from("users").select("catchphrase")
      .textSearch("catchphrase", query: "'fat' & 'cat'", config: "english", type: .plain)
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "catchphrase" : "'cat' 'fat'"
        }
      ]
      """
    }
  }

  @Test
  func textSearchWithPhrase() async throws {
    let res =
      try await client.from("users").select("catchphrase")
      .textSearch("catchphrase", query: "cat", config: "english", type: .phrase)
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "catchphrase" : "'cat' 'fat'"
        },
        {
          "catchphrase" : "'bat' 'cat'"
        }
      ]
      """
    }
  }

  @Test
  func textSearchWithWebsearch() async throws {
    let res =
      try await client.from("users").select("catchphrase")
      .textSearch("catchphrase", query: "'fat' & 'cat'", config: "english", type: .websearch)
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "catchphrase" : "'cat' 'fat'"
        }
      ]
      """
    }
  }

  @Test
  func multipleFilters() async throws {
    let res =
      try await client.from("users")
      .select("age_range,catchphrase,data,status,username")
      .eq("username", value: "supabot")
      .is("data", value: nil)
      .overlaps("age_range", value: "[1,2)")
      .eq("status", value: "ONLINE")
      .textSearch("catchphrase", query: "cat")
      .execute()
      .value as AnyJSON

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
  func filter() async throws {
    let res =
      try await client.from("users")
      .select("username")
      .filter("username", operator: "eq", value: "supabot")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func match() async throws {
    let res =
      try await client.from("users")
      .select("username,status")
      .match(["username": "supabot", "status": "ONLINE"])
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "status" : "ONLINE",
          "username" : "supabot"
        }
      ]
      """
    }
  }

  @Test
  func filterOnRpc() async throws {
    let res =
      try await client.rpc("get_username_and_status", params: ["name_param": "supabot"])
      .neq("status", value: "ONLINE")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [

      ]
      """
    }
  }
}
