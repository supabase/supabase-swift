//
//  RealtimeSampleApp.swift
//  RealtimeSample
//
//  Created by Guilherme Souza on 29/10/23.
//

import Supabase
import SwiftUI

@main
struct RealtimeSampleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

let supabase: SupabaseClient = {
  let client = SupabaseClient(
    supabaseURL: "https://project-id.supabase.co",
    supabaseKey: "anon key"
  )
  client.realtime.logger = { print($0) }
  return client
}()
