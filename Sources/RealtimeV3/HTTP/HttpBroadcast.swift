//
//  HttpBroadcast.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

// MARK: - HttpBroadcastMessage

/// A broadcast message for use with ``Realtime/httpBroadcastBatch(_:)``.
///
/// Each message carries a `topic`, an `event`, an `Encodable` payload,
/// and an optional `isPrivate` flag. Multiple messages may span different topics
/// in a single batch POST to the broadcast endpoint.
public struct HttpBroadcastMessage: Sendable {
  public let topic: String
  public let event: String
  public let payload: any Encodable & Sendable
  public let isPrivate: Bool

  public init(
    topic: String,
    event: String,
    payload: any Encodable & Sendable,
    isPrivate: Bool = false
  ) {
    self.topic = topic
    self.event = event
    self.payload = payload
    self.isPrivate = isPrivate
  }
}

// MARK: - Wire-format helpers (internal)

/// A single message element in the broadcast request body.
/// Encodable so the whole array can be serialized by `JSONEncoder`.
private struct BroadcastMessageBody: Encodable {
  let topic: String
  let event: String
  let payload: AnyJSON
  let `private`: Bool
}

/// Top-level request body: `{ "messages": [...] }`.
private struct BroadcastRequestBody: Encodable {
  let messages: [BroadcastMessageBody]
}

// MARK: - Realtime + httpBroadcastBatch

extension Realtime {

  /// Sends multiple broadcast messages across one or more topics in a single HTTP POST.
  ///
  /// Does **not** require an open WebSocket connection. Auth is injected via the
  /// `_HTTPClient` token provider when available; otherwise the `apikey` header is set.
  ///
  /// - Important: The `/api/broadcast` endpoint requires a **service-role** Bearer token
  ///   (or an access token with broadcast privileges). An anon JWT is rejected by the
  ///   server with HTTP 500 — surfaced here as ``RealtimeError/serverError(code:message:)``.
  ///
  /// - Parameter messages: One or more ``HttpBroadcastMessage`` values. Each `topic`
  ///   must be the **short** topic (without the `realtime:` prefix).
  /// - Throws: ``RealtimeError``
  public func httpBroadcastBatch(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError) {
    try await _httpBroadcastBatch(messages)
  }

  /// Internal workhorse called by both `httpBroadcastBatch` and `Channel.httpBroadcast`.
  func _httpBroadcastBatch(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError) {
    // Build the wire-format message array, encoding each payload via the shared helper
    // (honours Configuration.encoder's date/key strategies).
    var bodyMessages: [BroadcastMessageBody] = []
    for msg in messages {
      bodyMessages.append(
        BroadcastMessageBody(
          topic: msg.topic,
          event: msg.event,
          payload: try _encodeToJSON(msg.payload),
          private: msg.isPrivate
        )
      )
    }

    let requestBody = BroadcastRequestBody(messages: bodyMessages)

    // Determine whether a token is available for this call.
    // We can't call the actor-isolated accessTokenForJoin here because we are already
    // on the actor. Call the token logic directly (inline, actor-isolated).
    let currentToken: String?
    if let override = _overrideToken {
      currentToken = override
    } else if let provider = accessTokenProvider {
      do {
        currentToken = try await provider()
      } catch {
        throw .authenticationFailed(
          reason: "Access token provider threw an error.", underlying: error)
      }
    } else {
      currentToken = nil
    }

    // Auth header selection (spec §3.3, Finding E2):
    //   • Token available → "Authorization: Bearer <token>" (standard bearer auth)
    //   • No token       → "apikey: <key>" (anon/public channel access)
    // The _HTTPClient is built without a tokenProvider, so we inject auth explicitly.
    let headers: [String: String]
    if let token = currentToken {
      headers = ["Authorization": "Bearer \(token)"]
    } else {
      headers = ["apikey": apiKey]
    }

    // Build the absolute URL by appending "api/broadcast" to the HTTP base URL.
    // We use the absolute-URL overload of fetchData to preserve the full path prefix
    // (e.g. /realtime/v1) — the path-string overload replaces the path entirely.
    let broadcastURL = httpClient.host.appendingPathComponent("api/broadcast")

    do {
      _ = try await httpClient.fetchData(
        .post,
        url: broadcastURL,
        body: .encodable(requestBody),
        headers: headers
      )
    } catch let clientError as HTTPClientError {
      throw mapHTTPClientError(clientError)
    } catch {
      throw .transportFailure(underlying: error)
    }
  }
}

// MARK: - Channel + httpBroadcast

extension Channel {

  /// Sends a single broadcast message via HTTP POST (no WebSocket required).
  ///
  /// Delegates to ``Realtime/httpBroadcastBatch(_:)`` with a single-element batch
  /// whose topic is this channel's topic. The SDK-internal `realtime:` prefix is
  /// stripped before building the HTTP body (the endpoint matches WebSocket
  /// subscribers on the short topic).
  ///
  /// - Important: Like ``Realtime/httpBroadcastBatch(_:)``, the `/api/broadcast`
  ///   endpoint requires a **service-role** Bearer token; an anon JWT yields HTTP 500.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: An `Encodable & Sendable` payload.
  ///   - isPrivate: When `true`, the message is restricted to authenticated subscribers.
  /// - Throws: ``RealtimeError``
  public func httpBroadcast<T: Encodable & Sendable>(
    event: String,
    payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError) {
    guard let realtime else { throw .channelClosed(.clientDisconnected) }
    // `topic` is the WS channel topic, which is `realtime:`-prefixed. The HTTP
    // `/api/broadcast` endpoint expects the SHORT topic (no `realtime:` prefix) —
    // otherwise the message is accepted (202) but never delivered to subscribers.
    let shortTopic =
      topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
    let msg = HttpBroadcastMessage(
      topic: shortTopic,
      event: event,
      payload: payload,
      isPrivate: isPrivate
    )
    try await realtime._httpBroadcastBatch([msg])
  }
}

// MARK: - Error mapping

/// Maps an ``HTTPClientError`` returned by the broadcast endpoint to a ``RealtimeError``.
private func mapHTTPClientError(_ error: HTTPClientError) -> RealtimeError {
  switch error {
  case .responseError(let response, let data):
    let body = String(decoding: data, as: UTF8.self)
    switch response.statusCode {
    case 401, 403:
      return .authenticationFailed(reason: body, underlying: nil)
    case 429:
      return .rateLimited(retryAfter: nil)
    case 500...599:
      return .serverError(code: response.statusCode, message: body)
    default:
      return .broadcastFailed(reason: "HTTP \(response.statusCode): \(body)")
    }
  case .decodingError(_, let detail):
    return .broadcastFailed(reason: detail)
  case .unexpectedError(let msg):
    return .transportFailure(
      underlying: URLError(
        .cannotConnectToHost,
        userInfo: [NSLocalizedDescriptionKey: msg]
      ))
  }
}
