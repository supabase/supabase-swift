//
//  Channel+Routing.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

// MARK: - Frame router entry point

extension Channel {
  /// Called by the frame router when a message arrives for this channel's topic.
  ///
  /// Yields the frame to every event-feed subscriber; each per-call stream
  /// (`messages()`, `broadcasts`, presence, postgres) filters and decodes from there.
  ///
  /// Also handles server-initiated terminal events (`phx_close`, `phx_error`,
  /// and non-postgres `system` error frames) by transitioning to the appropriate
  /// `.closed` state. These routes guard on the current channel state so that a
  /// trailing `phx_close` from the server after our own `leave()` does NOT
  /// overwrite the already-set `.closed(.userRequested)` reason (idempotent).
  func receive(_ message: PhoenixMessage) {
    for continuation in eventContinuations.values {
      continuation.yield(.message(message))
    }
    // Channel-level reactions. `postgres_changes` frames and `system`
    // postgres-subscription errors are handled by the postgres transforms
    // themselves (they self-filter the feed), so they are not routed here.
    switch message.event {
    case .system:
      _routeSystemEvent(message)
    case .close:
      _handleServerClose(message)
    case .error:
      _handleServerError(message)
    default:
      break
    }
  }

  // MARK: - Server-initiated terminal event handlers

  /// Handles an unsolicited `phx_close` frame from the server.
  ///
  /// If the channel is already `.closed` (e.g. from our own `leave()`) or `.leaving`
  /// (our own leave is in progress), the frame is ignored so we never overwrite a
  /// user-requested close reason. Only unsolicited closes trigger a state transition.
  private func _handleServerClose(_ message: PhoenixMessage) {
    // Idempotency guard: ignore if already terminal or our own leave is in progress.
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    // Extract an optional message from the payload.
    let closeMessage: String?
    if case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    {
      closeMessage = obj["message"]?.stringValue
    } else {
      closeMessage = nil
    }

    log(
      .warn, .channel,
      "Server closed channel: \(closeMessage ?? "(no message)")",
      metadata: ["topic": topic]
    )

    // Clear shouldRejoin — a server-closed channel must not be auto-rejoined.
    shouldRejoin = false
    transition(to: .closed(.serverClosed(code: nil, message: closeMessage)))
  }

  /// Handles a `phx_error` frame from the server.
  ///
  /// Same idempotency guard as `_handleServerClose`: ignored when already terminal.
  private func _handleServerError(_ message: PhoenixMessage) {
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    let reason: String?
    if case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    {
      reason = obj["reason"]?.stringValue ?? obj["message"]?.stringValue
    } else {
      reason = nil
    }

    log(
      .error, .channel,
      "Server sent phx_error: \(reason ?? "(no reason)")",
      metadata: ["topic": topic]
    )

    shouldRejoin = false
    transition(to: .closed(.serverClosed(code: nil, message: reason)))
  }

  // MARK: - Postgres routing (Task 28)

  /// Returns the set of server-assigned subscription ids currently mapped to the given
  /// client registration UUID.
  ///
  /// Built from `serverIDRouting`, which is (re)built on every successful join/rejoin.
  /// A `postgresChanges(for:)` transform reads this live (per frame) to decide whether an
  /// incoming `postgres_changes` frame's `ids` array targets its registration.
  func postgresServerIDs(for registrationID: UUID) -> Set<Int> {
    var ids: Set<Int> = []
    for (serverID, registrationUUIDs) in serverIDRouting
    where registrationUUIDs.contains(registrationID) {
      ids.insert(serverID)
    }
    return ids
  }

  /// Routes an incoming `system` event.
  ///
  /// - If `extension == "postgres_changes"` and `status == "error"`: ignored here — the
  ///   postgres transforms self-filter this frame off the event feed and finish their own
  ///   streams with `.postgresSubscriptionFailed(reason:)`. The channel stays open.
  /// - Otherwise, if `status == "error"` and the message indicates an auth/token failure:
  ///   transitions the channel to `.closed(.unauthorized)` (server-initiated auth failure).
  /// - Otherwise, if `status == "error"` for any other reason:
  ///   transitions to `.closed(.serverClosed(code:message:))`.
  ///
  /// The channel-close path guards on the current state so it is idempotent when the
  /// channel is already `.closed` or `.leaving`.
  private func _routeSystemEvent(_ message: PhoenixMessage) {
    guard case .json(let jsonValue) = message.payload,
      let obj = jsonValue.objectValue
    else { return }

    let ext = obj["extension"]?.stringValue
    let status = obj["status"]?.stringValue
    let msgText = obj["message"]?.stringValue

    // postgres_changes subscription error → handled by the postgres transforms; channel stays open.
    if ext == "postgres_changes", status == "error" {
      let reason = msgText ?? "Unknown postgres subscription error"
      log(.error, .postgres, "Postgres subscription error: \(reason)", metadata: ["topic": topic])
      return
    }

    // Non-postgres system error → close the whole channel.
    guard status == "error" else { return }

    // Idempotency guard: if already terminal/leaving, do nothing.
    switch channelState {
    case .closed, .leaving:
      return
    default:
      break
    }

    let reason = msgText ?? "Unknown system error"
    log(.error, .channel, "System error: \(reason)", metadata: ["topic": topic])

    // Detect auth/token failures by looking for common keywords in the message.
    let lowerReason = reason.lowercased()
    let isAuthError =
      lowerReason.contains("token")
      || lowerReason.contains("auth")
      || lowerReason.contains("unauthorized")
      || lowerReason.contains("unauthenticated")
      || lowerReason.contains("forbidden")
      || lowerReason.contains("jwt")

    shouldRejoin = false
    if isAuthError {
      transition(to: .closed(.unauthorized))
    } else {
      transition(to: .closed(.serverClosed(code: nil, message: msgText)))
    }
  }

  /// Builds the server-id routing map from the join reply's `postgres_changes` response array.
  ///
  /// The server returns an array of objects in the same order as the client's `postgres_changes`
  /// entries. Each object has an `id` integer key. Multiple entries may share the same integer id
  /// (identical subscriptions collapse). We map `serverID -> [registrationUUID]`.
  func _buildServerIDRouting(from response: JSONValue) {
    var routing: [Int: [UUID]] = [:]
    guard let responseObj = response.objectValue,
      let changesArray = responseObj["postgres_changes"]?.arrayValue
    else {
      serverIDRouting = [:]
      return
    }

    // The changesArray indices correspond to pendingRegistrations indices.
    for (index, entry) in changesArray.enumerated() {
      guard let serverID = entry.objectValue?["id"]?.intValue,
        index < pendingRegistrations.count
      else { continue }
      let regUUID = pendingRegistrations[index].id
      if routing[serverID] == nil {
        routing[serverID] = [regUUID]
      } else {
        routing[serverID]?.append(regUUID)
      }
    }

    serverIDRouting = routing
  }
}
