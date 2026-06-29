//
//  IntegrationEnv.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import RealtimeV3

/// Environment configuration for the RealtimeV3 integration test suite.
///
/// All values default to the standard Supabase local dev stack (127.0.0.1:54321)
/// and can be overridden via environment variables for CI or remote instances.
enum IntegrationEnv {

  /// Base WebSocket URL for RealtimeV3 (no `/websocket` suffix).
  ///
  /// The SDK appends `/websocket` automatically in `_openConnection()` before dialling
  /// the transport, so callers should supply only the base path
  /// (e.g. `ws://127.0.0.1:54321/realtime/v1`). Kong routes the WebSocket upgrade
  /// to the Realtime server; the SDK appends the Phoenix endpoint path `/websocket`.
  static var realtimeURL: URL {
    ProcessInfo.processInfo.environment["SUPABASE_REALTIME_URL"]
      .flatMap(URL.init(string:))
      ?? URL(string: "ws://127.0.0.1:54321/realtime/v1")!
  }

  /// PostgREST REST endpoint for direct DB writes in postgres-change e2e tests.
  static var restURL: URL {
    ProcessInfo.processInfo.environment["SUPABASE_REST_URL"]
      .flatMap(URL.init(string:))
      ?? URL(string: "http://127.0.0.1:54321/rest/v1")!
  }

  /// Standard local anon JWT (demo key shipped with every local Supabase instance).
  /// Override via SUPABASE_ANON_KEY for non-standard instances.
  static var anonKey: String {
    ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
      ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  }

  /// Builds a fresh `Realtime` client pointed at the local instance.
  static func makeRealtime(configuration: Configuration = .default) -> Realtime {
    Realtime(url: realtimeURL, apiKey: anonKey, configuration: configuration)
  }

  /// Checks whether the local Supabase instance is reachable.
  ///
  /// Uses a lightweight HTTP GET to the REST root endpoint, passing the anon key as a
  /// header (not a query param — PostgREST would try to parse query params as filters).
  /// Avoids the overhead and potential scheduling races of a full WebSocket handshake.
  /// Returns `false` on any error so that tests are skipped when the instance is down.
  static func isReachable() async -> Bool {
    var request = URLRequest(url: restURL, timeoutInterval: 5)
    request.setValue(anonKey, forHTTPHeaderField: "apikey")

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse {
        // 200 means PostgREST answered normally.
        // Any 2xx/3xx/4xx means the server is up (even if this specific call is rejected).
        return (200..<500).contains(http.statusCode)
      }
      return false
    } catch {
      return false
    }
  }
}
