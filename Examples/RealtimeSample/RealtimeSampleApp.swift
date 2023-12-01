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
    supabaseURL: "https://nixfbjgqturwbakhnwym.supabase.co",
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5peGZiamdxdHVyd2Jha2hud3ltIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NzAzMDE2MzksImV4cCI6MTk4NTg3NzYzOX0.Ct6W75RPlDM37TxrBQurZpZap3kBy0cNkUimxF50HSo"
  )
  client.realtime.logger = { print($0) }
  return client
}()
