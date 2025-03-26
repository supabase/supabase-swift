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
  static let thirdPartyAuthWithClerk = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig["SUPABASE_URL"]!)!,
    supabaseKey: SupabaseConfig["SUPABASE_ANON_KEY"]!,
    options: SupabaseClientOptions(
      auth: SupabaseClientOptions.AuthOptions(
        accessToken: {
          try await Clerk.shared.session?.getToken()?.jwt
        }
      )
    )
  )
}
