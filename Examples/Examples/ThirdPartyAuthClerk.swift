//
//  ThirdPartyAuthClerk.swift
//  Examples
//
//  Created by Guilherme Souza on 26/03/25.
//

import Clerk
import Foundation
import Supabase

extension SupabaseClient {
  static let thirdPartyAuthWithClerk = try! SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
    supabaseKey: (SupabaseConfig["SUPABASE_PUBLISHABLE_KEY"] ?? SupabaseConfig["SUPABASE_ANON_KEY"])!,
    configuration: SupabaseClient.Configuration(
      auth: SupabaseClient.Configuration.Auth(
        accessToken: {
          try await Clerk.shared.session?.getToken()?.jwt
        }
      )
    )
  )
}
