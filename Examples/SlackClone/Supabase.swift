//
//  Supabase.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Foundation
import Supabase

let encoder: JSONEncoder = {
  let encoder = JSONEncoder.supabase()
  encoder.keyEncodingStrategy = .convertToSnakeCase
  return encoder
}()

let decoder: JSONDecoder = {
  let decoder = JSONDecoder.supabase()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  return decoder
}()

// swift-format-ignore: NeverUseForceTry
let supabase = try! SupabaseClient(
  supabaseURL: URL(string: "http://127.0.0.1:54321")!,
  supabaseKey:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  configuration: SupabaseClient.Configuration(
    database: .init(encoder: encoder, decoder: decoder),
    auth: .init(redirectTo: URL(string: "com.supabase.slack-clone://login-callback"))
  )
)
