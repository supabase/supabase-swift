//
//  LiveRealtime.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Realtime

/// Builds Realtime objects against the local Supabase stack.
///
/// There is no public Realtime client yet, so this goes through the `package` initializers.
enum LiveRealtime {
  static let baseURL = URL(string: "\(DotEnv.supabaseURL)/realtime/v1")!

  static func engine(apikey: String = DotEnv.supabasePublishableKey) -> RealtimeEngine {
    let url = RealtimeURL.webSocket(baseURL: baseURL, apikey: apikey, logLevel: nil)
    return RealtimeEngine(
      configuration: RealtimeEngineConfiguration(url: url),
      transport: URLSessionWebSocketTransport())
  }

  static func channel(
    _ topic: String,
    engine: RealtimeEngine,
    apikey: String = DotEnv.supabasePublishableKey,
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) -> RealtimeChannel {
    var configuration = RealtimeChannelConfiguration()
    configure(&configuration)
    let rest = RealtimeREST(
      baseURL: baseURL, apikey: apikey, http: HTTPClientConfiguration(), timeout: .seconds(10),
      clock: ContinuousClock(), accessToken: { apikey })
    return RealtimeChannel(topic: topic, configuration: configuration, engine: engine, rest: rest)
  }
}
