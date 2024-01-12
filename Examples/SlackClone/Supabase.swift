//
//  Supabase.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Foundation
import Supabase

let encoder: JSONEncoder = {
  let encoder = PostgrestClient.Configuration.jsonEncoder
  encoder.keyEncodingStrategy = .convertToSnakeCase
  return encoder
}()

let decoder: JSONDecoder = {
  let decoder = PostgrestClient.Configuration.jsonDecoder
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  return decoder
}()

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://xxpemjxnvjqnjjermerd.supabase.co")!,
  supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh4cGVtanhudmpxbmpqZXJtZXJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE1MTc3OTEsImV4cCI6MjAxNzA5Mzc5MX0.SLcEdwQEwZkif49WylKfQQv5ZiWRQdpDm8d2JhvBdtk",
  options: SupabaseClientOptions(
    db: .init(encoder: encoder, decoder: decoder),
    auth: SupabaseClientOptions.AuthOptions(
      storage: KeychainLocalStorage(service: "supabase", accessGroup: nil)
    )
  )
)
