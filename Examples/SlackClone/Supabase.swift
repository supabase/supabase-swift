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
  supabaseURL: URL(string: "https://rkehabxkxxpcbpzsammm.supabase.red")!,
  supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrZWhhYnhreHhwY2JwenNhbW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mjk3NTgzODgsImV4cCI6MjA0NTMzNDM4OH0.rTpPEGk9fMjHXXR49drfyF6IkrNYeL_-yGGDa1JaXTY",
  options: SupabaseClientOptions(
    db: .init(encoder: encoder, decoder: decoder),
    auth: .init(redirectToURL: URL(string: "com.supabase.slack-clone://login-callback")),
    global: SupabaseClientOptions.GlobalOptions(logger: SupaLogger())
  )
)
