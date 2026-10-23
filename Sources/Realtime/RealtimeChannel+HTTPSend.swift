//
//  RealtimeChannel+HTTPSend.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

public import Foundation
import HTTPTypes
import Helpers

extension RealtimeChannel {
  /// Sends a broadcast message via the REST API using a `Codable` payload.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. Use it when you need guaranteed REST delivery or want to send
  /// a broadcast before subscribing to the channel.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0. Older servers don't expose
  /// > the per-event `/api/broadcast/{topic}/events/{event}` endpoint this method targets.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A `Codable` value to send as the message payload.
  ///   - timeout: An optional timeout. Defaults to the socket's configured timeout.
  /// - Throws: ``RealtimeError`` with kind `.accessTokenMissing`, `.server`, `.transport` or `.timeout`.
  public func httpSend(
    event: String,
    message: some Codable,
    timeout: Duration? = nil
  ) async throws {
    try await httpSend(event: event, message: JSONObject(message), timeout: timeout)
  }

  /// Sends a broadcast message via the REST API using a raw `JSONObject` payload.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. Use it when you need guaranteed REST delivery or want to send
  /// a broadcast before subscribing to the channel.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0. Older servers don't expose
  /// > the per-event `/api/broadcast/{topic}/events/{event}` endpoint this method targets.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A ``JSONObject`` to send as the message payload.
  ///   - timeout: An optional timeout. Defaults to the socket's configured timeout.
  /// - Throws: ``RealtimeError`` with kind `.accessTokenMissing`, `.server`, `.transport` or `.timeout`.
  public func httpSend(
    event: String,
    message: JSONObject,
    timeout: Duration? = nil
  ) async throws {
    try await httpSend(
      event: event,
      body: try JSONEncoder.supabase().encode(message),
      contentType: "application/json",
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
  /// > Important: Requires a Realtime server version >= 2.97.0.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the request body.
  ///   - timeout: An optional timeout. Defaults to the socket's configured timeout.
  /// - Throws: ``RealtimeError`` with kind `.accessTokenMissing`, `.server`, `.transport` or `.timeout`.
  public func httpSend(
    event: String,
    data: Data,
    timeout: Duration? = nil
  ) async throws {
    try await httpSend(
      event: event, body: data, contentType: "application/octet-stream", timeout: timeout)
  }

  private func httpSend(
    event: String,
    body: Data,
    contentType: String,
    timeout: Duration?
  ) async throws {
    guard let accessToken = await connection.refreshToken() else {
      throw RealtimeError.accessTokenMissing
    }

    var headers: HTTPFields = [.contentType: contentType]
    if let apiKey = connection.options.apikey {
      headers[.apiKey] = apiKey
    }
    headers[.authorization] = "Bearer \(accessToken)"

    let request = HTTPRequest(
      method: .post,
      url: connection.broadcastURL(topic: subTopic, event: event, isPrivate: config.isPrivate),
      headerFields: headers
    )

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await withTimeout(
        timeout ?? connection.options.timeout, clock: connection.options.clock
      ) {
        try await connection.http.send(request, body: body)
      }
    } catch is TimeoutError {
      throw RealtimeError(kind: .timeout, message: "httpSend() timed out.")
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError` and errors
      // thrown by a custom `ClientTransport` or the `accessToken` closure propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      // `URLSession` reports a cancelled `Task` as `URLError(.cancelled)`. A `.cancelled` with no
      // task cancellation behind it (a middleware cancelled the request) stays a transport error.
      if urlError.code == .cancelled, Task.isCancelled { throw CancellationError() }
      throw RealtimeError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    guard response.status.code == 202 else {
      var errorMessage = "Status Code: \(response.status.code)"
      if let errorBody = try? data.decoded(as: [String: String].self) {
        errorMessage = errorBody["error"] ?? errorBody["message"] ?? errorMessage
      }
      throw RealtimeError(
        kind: .server, message: errorMessage, response: HTTPErrorResponse(response, body: data))
    }
  }
}
