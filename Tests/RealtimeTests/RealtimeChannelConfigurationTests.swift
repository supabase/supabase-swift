//
//  RealtimeChannelConfigurationTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import InlineSnapshotTesting
import Testing

@testable import Realtime

@Suite
struct RealtimeChannelConfigurationTests {
  private func joinPayload(
    _ configuration: RealtimeChannelConfiguration, bindings: [PostgresJoinConfig] = []
  ) -> RealtimeJoinPayload {
    RealtimeJoinPayload(
      config: RealtimeJoinConfig(configuration, bindings: bindings), accessToken: "token",
      version: nil)
  }

  @Test
  func defaultConfiguration() {
    assertInlineSnapshot(of: joinPayload(RealtimeChannelConfiguration()), as: .json) {
      """
      {
        "access_token" : "token",
        "config" : {
          "broadcast" : {
            "ack" : false,
            "replication_ready" : false,
            "self" : false
          },
          "postgres_changes" : [

          ],
          "presence" : {
            "enabled" : false,
            "key" : ""
          },
          "private" : false
        }
      }
      """
    }
  }

  @Test
  func privateChannelWithAcknowledgedOwnBroadcastsAndReplay() {
    var configuration = RealtimeChannelConfiguration()
    configuration.isPrivate = true
    configuration.broadcast.acknowledge = true
    configuration.broadcast.receiveOwnMessages = true
    configuration.broadcast.waitForReplication = true
    configuration.broadcast.replay = .init(since: Date(timeIntervalSince1970: 1), limit: 10)

    assertInlineSnapshot(of: joinPayload(configuration), as: .json) {
      """
      {
        "access_token" : "token",
        "config" : {
          "broadcast" : {
            "ack" : true,
            "replay" : {
              "limit" : 10,
              "since" : 1000
            },
            "replication_ready" : true,
            "self" : true
          },
          "postgres_changes" : [

          ],
          "presence" : {
            "enabled" : false,
            "key" : ""
          },
          "private" : true
        }
      }
      """
    }
  }

  @Test
  func presenceKey() {
    var configuration = RealtimeChannelConfiguration()
    configuration.presence.key = "user-1"

    assertInlineSnapshot(of: joinPayload(configuration).config.presence, as: .json) {
      """
      {
        "enabled" : false,
        "key" : "user-1"
      }
      """
    }
  }

  @Test
  func bindingsAreSentInOrder() {
    let bindings = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "todos", filter: "list_id=eq.1"),
      PostgresJoinConfig(event: .all, schema: "public", table: "lists", select: ["id", "name"]),
    ]

    assertInlineSnapshot(
      of: joinPayload(RealtimeChannelConfiguration(), bindings: bindings).config.postgresChanges,
      as: .json
    ) {
      """
      [
        {
          "event" : "INSERT",
          "filter" : "list_id=eq.1",
          "schema" : "public",
          "table" : "todos"
        },
        {
          "event" : "*",
          "schema" : "public",
          "select" : [
            "id",
            "name"
          ],
          "table" : "lists"
        }
      ]
      """
    }
  }

  @Test
  func waitForSubscriptionAsksTheServerToHoldTheJoinReply() {
    var configuration = RealtimeChannelConfiguration()
    configuration.postgresChanges.waitForSubscription = true
    let bindings = [PostgresJoinConfig(event: .all, schema: "public", table: "todos")]

    assertInlineSnapshot(of: joinPayload(configuration, bindings: bindings), as: .json) {
      """
      {
        "access_token" : "token",
        "config" : {
          "broadcast" : {
            "ack" : false,
            "replication_ready" : false,
            "self" : false
          },
          "postgres_changes" : [
            {
              "event" : "*",
              "schema" : "public",
              "table" : "todos"
            }
          ],
          "postgres_changes_options" : {
            "wait" : true
          },
          "presence" : {
            "enabled" : false,
            "key" : ""
          },
          "private" : false
        }
      }
      """
    }
  }
}
