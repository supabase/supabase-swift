//
//  LiveRealtime.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import HTTPTypes
import Realtime

/// Builds Realtime clients against the local Supabase stack.
enum LiveRealtime {
  static let url = URL(string: "\(DotEnv.supabaseURL)/realtime/v1")!

  static func client(
    apikey: String = DotEnv.supabasePublishableKey,
    configure: (inout RealtimeClientOptions) -> Void = { _ in }
  ) -> RealtimeClient {
    var options = RealtimeClientOptions()
    options.headers[HTTPField.Name("apikey")!] = apikey
    configure(&options)
    return RealtimeClient(url: url, options: options)
  }
}
