//
//  Realtime+Broadcast.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

/// A single message to broadcast via the HTTP broadcast endpoint.
public struct HttpBroadcastMessage: Sendable {
  public let topic: String
  public let event: String
  /// The payload to broadcast. Must be `Encodable` and `Sendable`.
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

extension Realtime {
  // MARK: - HTTP Broadcast (one-shot, no WebSocket required)

  /// Broadcasts a single typed message via HTTP POST.
  ///
  /// This does not open a WebSocket connection. Use it for fire-and-forget scenarios where
  /// persistent subscriptions are not needed.
  ///
  /// - Parameters:
  ///   - topic: The channel topic to broadcast on.
  ///   - event: The broadcast event name.
  ///   - payload: An `Encodable` value to send as the JSON payload.
  ///   - isPrivate: When `true`, only authenticated subscribers receive the message.
  public func httpBroadcast<T: Encodable & Sendable>(
    topic: String,
    event: String,
    payload: T,
    isPrivate: Bool = false
  ) async throws(RealtimeError) {
    let msg = HttpBroadcastMessage(
      topic: topic, event: event, payload: payload, isPrivate: isPrivate)
    try await httpBroadcast([msg])
  }

  /// Broadcasts multiple messages via HTTP POST in a single request.
  ///
  /// - Parameter messages: The messages to broadcast.
  public func httpBroadcast(_ messages: [HttpBroadcastMessage]) async throws(RealtimeError) {
    let token = try await resolveTokenForHTTP()

    let httpURL = buildHTTPBroadcastURL()

    var bodyMessages: [[String: JSONValue]] = []
    for m in messages {
      let payloadDict: [String: JSONValue]
      do {
        let data = try configuration.encoder.encode(m.payload)
        payloadDict = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
      } catch {
        throw .encoding(underlying: error)
      }

      var entry: [String: JSONValue] = [
        "topic": .string(m.topic),
        "event": .string(m.event),
        "payload": .object(payloadDict),
      ]
      if m.isPrivate { entry["private"] = true }
      bodyMessages.append(entry)
    }

    let bodyData: Data
    do {
      bodyData = try JSONEncoder().encode(["messages": bodyMessages])
    } catch {
      throw .encoding(underlying: error)
    }

    var request = URLRequest(url: httpURL)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        if http.statusCode == 429 {
          throw RealtimeError.rateLimited(retryAfter: nil)
        }
        throw RealtimeError.serverError(
          code: http.statusCode,
          message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        )
      }
    } catch let e as RealtimeError {
      throw e
    } catch {
      throw .transportFailure(underlying: error)
    }
  }
}

// MARK: - Private helpers

extension Realtime {
  /// Resolves the API key for use in HTTP requests.
  func resolveTokenForHTTP() async throws(RealtimeError) -> String {
    do {
      return try await resolveToken()
    } catch {
      throw .authenticationFailed(reason: error.localizedDescription, underlying: nil)
    }
  }

  /// Builds the HTTP broadcast endpoint URL from the WebSocket URL.
  private func buildHTTPBroadcastURL() -> URL {
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    comps.scheme = (comps.scheme == "wss") ? "https" : "http"
    comps.path = "/realtime/v1/api/broadcast"
    comps.queryItems = nil
    return comps.url ?? url
  }
}
