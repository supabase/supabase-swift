//
//  SystemEventPayload.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation
import Helpers

/// The decoded payload of a Phoenix `system` event: `{ extension, status, message }`.
///
/// Centralizes the wire-key strings (notably the `"postgres_changes"` extension name) and the
/// parse shape shared by the join-confirmation wait (`Channel._awaitPostgresSubscribed`), the
/// channel system router (`Channel._routeSystemEvent`), and the postgres transforms
/// (`Channel.postgresChanges(for:)`).
struct SystemEventPayload {
  let extensionName: String?
  let status: String?
  let message: String?

  /// Parses `message` when it is a `system` event carrying a JSON object payload; otherwise `nil`.
  init?(_ message: PhoenixMessage) {
    guard message.event == .system,
      case .json(let json) = message.payload,
      let obj = json.objectValue
    else { return nil }
    self.extensionName = obj["extension"]?.stringValue
    self.status = obj["status"]?.stringValue
    self.message = obj["message"]?.stringValue
  }

  /// Whether this system event concerns the `postgres_changes` extension.
  var isPostgresChanges: Bool { extensionName == "postgres_changes" }
}
