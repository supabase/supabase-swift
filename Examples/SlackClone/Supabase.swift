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
  supabaseURL: URL(string: "https://SUPABASE_URL.com")!,
  supabaseKey: "SUPABASE_ANON_KEY",
  options: SupabaseClientOptions(db: .init(encoder: encoder, decoder: decoder))
)
