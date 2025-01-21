//
//  PostgrestFilterTests.swift
//
//
//  Created by Guilherme Souza on 06/05/24.
//

import InlineSnapshotTesting
import PostgREST
import XCTest

final class PostgrestFilterTests: XCTestCase {
  let client = PostgrestClient(
    configuration: PostgrestClient.Configuration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1")!,
      headers: [
        "apikey": DotEnv.SUPABASE_ANON_KEY
      ],
      logger: nil
    )
  )

  func testNot() async throws {
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
        },
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  func testOr() async throws {
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

  func testEq() async throws {
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

  func testNeq() async throws {
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
        },
        {
          "username" : "jsonuser"
        }
      ]
      """
    }
  }

  func testGt() async throws {
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
        },
        {
          "id" : 4
        }
      ]
      """
    }
  }

  func testGte() async throws {
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
        },
        {
          "id" : 4
        }
      ]
      """
    }
  }

  func testLe() async throws {
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

  func testLte() async throws {
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

  func testLike() async throws {
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

  func testLikeAllOf() async throws {
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

  func testLikeAnyOf() async throws {
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

  func testIlike() async throws {
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

  func testIlikeAllOf() async throws {
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

  func testIlikeAnyOf() async throws {
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

  func testIs() async throws {
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

  func testIn() async throws {
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
        },
        {
          "status" : "ONLINE"
        }
      ]
      """
    }
  }

  func testContains() async throws {
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

  func testContainedBy() async throws {
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

  func testRangeLt() async throws {
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

  func testRangeGt() async throws {
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

  func testRangeLte() async throws {
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

  func testRangeGte() async throws {
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
        },
        {
          "age_range" : "[20,30)"
        }
      ]
      """
    }
  }

  func testRangeAdjacent() async throws {
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

  func testOverlaps() async throws {
    let res =
      try await client.from("users").select("age_range").overlaps("age_range", value: "[2,25)")
      .execute()
      .value as AnyJSON

    assertInlineSnapshot(of: res, as: .json) {
      """
      [
        {
          "age_range" : "[20,30)"
        },
        {
          "age_range" : "[20,30)"
        }
      ]
      """
    }
  }

  func testTextSearch() async throws {
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

  func testTextSearchWithPlain() async throws {
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

  func testTextSearchWithPhrase() async throws {
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

  func testTextSearchWithWebsearch() async throws {
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

  func testMultipleFilters() async throws {
    let res =
      try await client.from("users")
      .select()
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

  func testFilter() async throws {
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

  func testMatch() async throws {
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

  func testFilterOnRpc() async throws {
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
