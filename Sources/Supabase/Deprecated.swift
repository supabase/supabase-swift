//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 15/05/24.
//

import Alamofire
import Foundation

extension SupabaseClient {
  /// Database client for Supabase.
  @available(
    *,
    deprecated,
    message:
      "Direct access to database is deprecated, please use one of the available methods such as, SupabaseClient.from(_:), SupabaseClient.rpc(_:params:), or SupabaseClient.schema(_:)."
  )
  public var database: PostgrestClient {
    rest
  }

  /// Realtime client for Supabase
  @available(*, deprecated, message: "Use realtimeV2")
  public var realtime: RealtimeClient {
    _realtime.value
  }
}

extension SupabaseClientOptions.GlobalOptions {
  @available(
    *, deprecated,
    message:
      "Use init(headers:alamofireSession:logger:) instead. This initializer will be removed in a future version."
  )
  public init(
    headers: [String: String] = [:],
    session: URLSession,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.init(
      headers: headers,
      alamofireSession: Alamofire.Session(
        session: session, delegate: SessionDelegate(),
        rootQueue: DispatchQueue(label: "com.supabase.session")),
      logger: logger
    )
  }
}
