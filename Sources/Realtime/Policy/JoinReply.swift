//
//  JoinReply.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers

func serverChanges(fromJoinReply response: JSONObject) throws -> [PostgresJoinConfig] {
  try response[ChannelEvent.postgresChanges]?.decode(as: [PostgresJoinConfig].self) ?? []
}

/// Whether the server accepted the `postgres_changes` bindings the join sent, as supabase-js
/// checks them: entry `i` of the reply has the event, schema, table, and filter of entry `i` the
/// join sent.
func postgresChangesMatch(sent: [PostgresJoinConfig], server: [PostgresJoinConfig]) -> Bool {
  sent.count <= server.count
    && zip(sent, server).allSatisfy { sent, server in
      sent.event == server.event && sent.schema == server.schema && sent.table == server.table
        && sent.filter == server.filter
    }
}
