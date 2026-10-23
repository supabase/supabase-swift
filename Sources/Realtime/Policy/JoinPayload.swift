//
//  JoinPayload.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers

/// Builds the `phx_join` payload for a channel.
///
/// An open presence stream turns presence on, so the server only tracks presence for channels
/// that read it. The `postgres_changes` array follows the order the streams were opened in.
///
/// - Parameters:
///   - bindings: The channel's open streams, in registration order.
///   - accessToken: The token sent as `access_token`, or `nil` to omit it.
///   - version: The client version sent as `version`, or `nil` to omit it.
func joinPayload(
  config: RealtimeChannelConfig,
  bindings: [ChannelBinding],
  accessToken: String?,
  version: String?
) throws -> JSONObject {
  var presence = config.presence
  presence.enabled = bindings.contains(where: \.isPresence)

  return try JSONObject(
    JoinPayload(
      config: JoinConfig(
        broadcast: config.broadcast,
        presence: presence,
        postgresChanges: bindings.compactMap {
          if case .postgres(let change) = $0 { change } else { nil }
        },
        isPrivate: config.isPrivate
      ),
      accessToken: accessToken,
      version: version
    )
  )
}

private struct JoinPayload: Encodable {
  var config: JoinConfig
  var accessToken: String?
  var version: String?

  enum CodingKeys: String, CodingKey {
    case config
    case accessToken = "access_token"
    case version
  }
}

private struct JoinConfig: Encodable {
  var broadcast: BroadcastJoinConfig
  var presence: PresenceJoinConfig
  var postgresChanges: [PostgresJoinConfig]
  var isPrivate: Bool

  enum CodingKeys: String, CodingKey {
    case broadcast
    case presence
    case isPrivate = "private"
    case postgresChanges = "postgres_changes"
  }
}
