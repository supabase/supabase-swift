//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 15/05/24.
//

import Foundation

extension SupabaseClient {
  /// Database client for Supabase.
  @available(
    *,
    deprecated,
    message: "Direct access to database is deprecated, please use one of the available methods such as, SupabaseClient.from(_:), SupabaseClient.rpc(_:params:), or SupabaseClient.schema(_:)."
  )
  public var database: PostgrestClient {
    rest
  }
}
