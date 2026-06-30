//
//  JoinPayload.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

// MARK: - JoinPayload

/// The wire-format payload for a `phx_join` frame.
///
/// Shape mirrors `RealtimeJoinPayload` / `RealtimeJoinConfig` from the v2 module.
/// For Phase 3, `postgresChanges` is always an empty array.
struct JoinPayload: Codable {
  var config: JoinConfig
  var accessToken: String?

  enum CodingKeys: String, CodingKey {
    case config
    case accessToken = "access_token"
  }
}

// MARK: - JoinConfig

struct JoinConfig: Codable {
  var broadcast: BroadcastJoinConfig
  var presence: PresenceJoinConfig
  var postgresChanges: [JSONObject]
  var isPrivate: Bool

  enum CodingKeys: String, CodingKey {
    case broadcast
    case presence
    case postgresChanges = "postgres_changes"
    case isPrivate = "private"
  }
}

// MARK: - BroadcastJoinConfig

struct BroadcastJoinConfig: Codable {
  var ack: Bool
  var `self`: Bool
  var replay: BroadcastReplayConfig?
}

// MARK: - BroadcastReplayConfig

struct BroadcastReplayConfig: Codable {
  /// Unix timestamp in milliseconds.
  var since: Int
  var limit: Int?
}

// MARK: - PresenceJoinConfig

struct PresenceJoinConfig: Codable {
  var key: String
  var enabled: Bool
}

// MARK: - Factory

extension JoinPayload {
  /// Builds a `JoinPayload` from `ChannelOptions`, an optional access token, and
  /// the channel's pending postgres-changes registrations.
  ///
  /// Each `ChangeRegistrationConfig` in `registrations` is serialised to a
  /// `JSONObject` with keys `event`, `schema`, `table`, and (if non-nil) `filter`,
  /// matching the wire shape Phoenix expects.
  static func make(
    from options: ChannelOptions,
    accessToken: String?,
    registrations: [ChangeRegistrationConfig] = []
  ) -> JoinPayload {
    let replayConfig: BroadcastReplayConfig?
    if let replay = options.broadcast.replay {
      replayConfig = BroadcastReplayConfig(
        since: Int(replay.since.timeIntervalSince1970 * 1000),
        limit: replay.limit
      )
    } else {
      replayConfig = nil
    }

    let broadcastConfig = BroadcastJoinConfig(
      ack: options.broadcast.acknowledge,
      self: options.broadcast.receiveOwnBroadcasts,
      replay: replayConfig
    )

    let presenceConfig = PresenceJoinConfig(
      key: options.presence.key ?? "",
      enabled: options.presence.enabled
    )

    // Serialise each registration into a JSONObject entry.
    let postgresChanges: [JSONObject] = registrations.map { reg in
      var entry: JSONObject = [
        "event": .string(reg.event.rawValue),
        "schema": .string(reg.schema),
        "table": .string(reg.table),
      ]
      if let filter = reg.filter {
        entry["filter"] = .string(filter)
      }
      return entry
    }

    let config = JoinConfig(
      broadcast: broadcastConfig,
      presence: presenceConfig,
      postgresChanges: postgresChanges,
      isPrivate: options.isPrivate
    )

    return JoinPayload(config: config, accessToken: accessToken)
  }

  /// Encodes the payload to a `JSONObject` suitable for embedding in the phx_join frame.
  func toJSONObject() throws -> JSONObject {
    try JSONObject(self)
  }
}
