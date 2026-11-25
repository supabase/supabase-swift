//
//  RealtimeChannel+HTTPSend.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

public import Foundation
internal import HTTPTypes
import Helpers

extension RealtimeChannel {
  /// Sends a broadcast message via the REST API.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. Use it when you need guaranteed REST delivery or want to send
  /// a broadcast before subscribing to the channel.
  ///
  /// The request carries the client's configured headers, including `X-Client-Info` and
  /// `apikey`, with `Content-Type` and, when the client has an access token,
  /// `Authorization: Bearer <access token>` set on top. Without a token only `apikey`
  /// authenticates the request, which is enough for a public channel; a private channel needs a
  /// token its RLS policies accept. The request is sent once and never retried, because a replay
  /// can deliver the broadcast twice.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0. Older servers don't expose
  /// > the per-event `/api/broadcast/{topic}/events/{event}` endpoint this method targets.
  ///
  /// With `persist`, the server also stores the message for broadcast replay. The SDK sends it
  /// in the query string, as `persist=true` or `persist[ttl]=3600`, never in the body. A ttl
  /// the server does not allow fails the call with `.server` and the server's message.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: The value to send as the JSON request body.
  ///   - persist: Asks the server to store the message. `nil` sends no persistence request.
  ///     It needs a private channel.
  ///   - timeout: How long the call may take, including the access token fetch, like every
  ///     other Realtime timeout. `nil` uses ``RealtimeClient/Configuration/requestTimeout``.
  ///     ``RealtimeClient/Configuration/http`` explains the idle timeout.
  ///   - encoder: The encoder for `payload`. `nil` uses `JSONEncoder.supabase()`.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when `payload` does not encode, or
  ///   when `persist` is set on a channel that is not private, and nothing is sent;
  ///   `.accessToken` when the `accessToken` closure throws; `.server`, `.transport`, `.timeout`
  ///   when `timeout` runs out, `.channelRemoved`, or `.notConnected` when the client was
  ///   released.
  public func httpSend(
    event: String,
    payload: some Encodable,
    persist: BroadcastPersistence? = nil,
    timeout: Duration? = nil,
    encoder: JSONEncoder? = nil
  ) async throws {
    try checkCanPersist(persist)
    let body: Data
    do {
      body = try (encoder ?? JSONValue.encoder).encode(payload)
    } catch {
      throw RealtimeError.invalidRequest(
        "The payload cannot be encoded as JSON.", underlyingError: error)
    }
    try await httpSend(
      event: event,
      body: body,
      contentType: "application/json",
      persist: persist,
      timeout: timeout
    )
  }

  /// Sends a binary broadcast message via the REST API.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. The payload is sent as-is with an `application/octet-stream`
  /// content type — use this for raw binary payloads (e.g. images, custom binary formats)
  /// that shouldn't be JSON-encoded.
  ///
  /// Headers, retry and `persist` follow ``httpSend(event:payload:persist:timeout:encoder:)``.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the request body.
  ///   - persist: Asks the server to store the message. `nil` sends no persistence request.
  ///     It needs a private channel.
  ///   - timeout: How long the call may take, including the access token fetch, like every
  ///     other Realtime timeout. `nil` uses ``RealtimeClient/Configuration/requestTimeout``.
  ///     ``RealtimeClient/Configuration/http`` explains the idle timeout.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when `persist` is set on a channel
  ///   that is not private, and nothing is sent; `.accessToken` when the `accessToken` closure
  ///   throws; `.server`, `.transport`, `.timeout` when `timeout` runs out, `.channelRemoved`,
  ///   or `.notConnected` when the client was released.
  public func httpSend(
    event: String,
    data: Data,
    persist: BroadcastPersistence? = nil,
    timeout: Duration? = nil
  ) async throws {
    try checkCanPersist(persist)
    try await httpSend(
      event: event, body: data, contentType: "application/octet-stream", persist: persist,
      timeout: timeout)
  }

  private func httpSend(
    event: String,
    body: Data,
    contentType: String,
    persist: BroadcastPersistence?,
    timeout: Duration?
  ) async throws {
    let client = try clientForAction()
    try await client.checkUsable(self)
    var headers = client.headers
    headers[.contentType] = contentType
    let url = client.broadcastURL(
      topic: topic, event: event, isPrivate: configuration.isPrivate, persist: persist)

    let response: HTTPResponse
    let data: Data
    do {
      // The token fetch is inside the timeout, so a callback that hangs fails the send as `.timeout`.
      (response, data) = try await withTimeout(
        timeout ?? client.configuration.requestTimeout, clock: client.clock
      ) { [headers] in
        var headers = headers
        // Without a token, an `Authorization` from `headers` goes too: it may hold the token of
        // a user who signed out, and the server falls back to `apikey`.
        headers[.authorization] = try await client.httpSendAccessToken().map { "Bearer \($0)" }
        let request = HTTPRequest(method: .post, url: url, headerFields: headers)
        return try await client.http.send(request, body: body)
      }
    } catch is TimeoutError {
      throw RealtimeError(kind: .timeout, message: "httpSend() timed out.")
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError` and errors
      // thrown by a custom `ClientTransport` propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      throw RealtimeError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    guard response.status.code == 202 else {
      var errorMessage = "Status Code: \(response.status.code)"
      if let errorBody = try? data.decoded(as: JSONObject.self),
        let message = errorBody["error"]?.stringValue ?? errorBody["message"]?.stringValue
      {
        errorMessage = message
      }
      throw RealtimeError(
        kind: .server, message: errorMessage, response: HTTPErrorResponse(response, body: data))
    }
  }
}
