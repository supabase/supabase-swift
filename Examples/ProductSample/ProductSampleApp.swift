//
//  ProductSampleApp.swift
//  ProductSample
//
//  Created by Guilherme Souza on 18/10/23.
//

import Supabase
import SwiftUI

@main
struct ProductSampleApp: App {
  var body: some Scene {
    WindowGroup {
      AppView()
    }
  }
}

let supabase = SupabaseClient(
  supabaseURL: URL(string: Config.SUPABASE_URL)!,
  supabaseKey: Config.SUPABASE_ANON_KEY
)
