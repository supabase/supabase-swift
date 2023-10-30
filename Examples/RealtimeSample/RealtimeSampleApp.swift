//
//  RealtimeSampleApp.swift
//  RealtimeSample
//
//  Created by Guilherme Souza on 29/10/23.
//

import Realtime
import SwiftUI

@main
struct RealtimeSampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

let socket: RealtimeClient = {
  let client = RealtimeClient(
    "https://PROJECT_ID.supabase.co/realtime/v1",
    params: [
      "apikey": "SUPABASE_ANON_KEY",
    ]
  )
  client.logger = { print($0) }
  return client
}()
