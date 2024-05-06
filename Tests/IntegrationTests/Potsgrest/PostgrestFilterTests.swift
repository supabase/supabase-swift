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
        "apikey": DotEnv.SUPABASE_ANON_KEY,
      ],
      logger: nil
    )
  )

  func testNot() async throws {
    let res = try await client.from("users")
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

  func testOr() async throws {
    let res = try await client.from("users")
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
    let res = try await client.from("users")
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
    let res = try await client.from("users")
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
}
